"""Quickshell-owned offline dictation worker. Its stdin/stdout carry JSON lines."""

import asyncio
from collections import deque
from concurrent.futures import ThreadPoolExecutor
import ctypes
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import sys
import traceback
import unicodedata


RATE = 16000
FRAME = RATE // 50
FRAME_BYTES = FRAME * 2
MODELS = {"tiny", "base", "small", "medium", "large-v3-turbo"}
DATA = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
FEATURE_DATA = DATA / "caelestia/voice-typing"
MODELS_DIR = FEATURE_DATA / "models"
TEXT_INPUT = FEATURE_DATA / "type-text"
TEXT_FRAGMENT_SIZE = 40
REQUIRED_MODEL_FILES = ("model.bin", "config.json", "tokenizer.json")
os.environ.update(HF_HUB_OFFLINE="1", HF_HUB_DISABLE_TELEMETRY="1")


class VoiceError(Exception):
    pass


def emit(**message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


async def command(*args, payload=None):
    try:
        proc = await asyncio.create_subprocess_exec(
            *args, stdin=asyncio.subprocess.DEVNULL if payload is None else asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
        )
    except OSError as error:
        raise VoiceError(f"{args[0]} is unavailable") from error
    try:
        out, _ = await asyncio.wait_for(proc.communicate(payload), 2)
    except (asyncio.TimeoutError, asyncio.CancelledError):
        if proc.returncode is None:
            proc.kill()
        await proc.wait()
        raise
    return proc.returncode, out


class SpeechChunks:
    """Disjoint utterances, with a short look-behind and a bounded wait for a pause."""

    def __init__(self, pause_ms, maximum_ms):
        self.pause = pause_ms // 20
        self.maximum = maximum_ms // 20
        self.lead = deque(maxlen=10)
        self.frames = []
        self.voice_flags = []
        self.quiet = 0
        self.voiced = 0
        self.noise = 0.002

    def feed(self, frame):
        rms = math.sqrt(sum(x * x for x in struct.unpack("<320h", frame)) / FRAME) / 32768
        talking = rms > max(0.004, self.noise * 3.2)
        if not self.frames and not talking:
            self.noise = self.noise * 0.98 + rms * 0.02
            self.lead.append(frame)
            return rms, None
        if not self.frames:
            self.frames.extend(self.lead)
            self.voice_flags.extend([False] * len(self.lead))
            self.lead.clear()
        self.frames.append(frame)
        self.voice_flags.append(talking)
        self.quiet = 0 if talking else self.quiet + 1
        self.voiced += int(talking)
        if self.quiet >= self.pause:
            return rms, self.flush()
        if len(self.frames) >= self.maximum:
            # A brief gap near the deadline is a better boundary than a cut mid-word.
            for cut in range(len(self.frames) - 5, len(self.frames) - 30, -1):
                if not any(self.voice_flags[cut - 3:cut + 3]):
                    chunk = b"".join(self.frames[:cut])
                    del self.frames[:cut]
                    del self.voice_flags[:cut]
                    self.voiced = sum(self.voice_flags)
                    return rms, chunk
            return rms, self.flush()
        return rms, None

    def flush(self):
        # Retain a little trailing silence for the decoder.
        end = len(self.frames) - max(0, self.quiet - 9)
        pcm = b"".join(self.frames[:end]) if self.voiced >= 11 else b""
        self.frames.clear()
        self.voice_flags.clear()
        self.quiet = self.voiced = 0
        return pcm


@dataclass(frozen=True)
class Word:
    text: str
    start: float
    end: float
    probability: float = 1.0

    @property
    def key(self):
        normalized = unicodedata.normalize("NFKC", self.text).strip().casefold()
        return re.sub(r"^[^\w]+|[^\w]+$", "", normalized) or normalized


def render_words(words):
    text = "".join(word.text for word in words)
    return " ".join("".join(
        " " if ch.isspace() or unicodedata.category(ch) in {"Cc", "Cf"} else ch
        for ch in text
    ).split())


class StreamingText:
    """Commit agreement between successive decodes of a single audio span."""

    def __init__(self):
        self.previous = []
        self.committed = []

    def align(self, words):
        count = len(self.committed)
        if not count:
            return 0, True
        if len(words) >= count and all(
            old.key == new.key and abs(old.end - new.end) <= 0.38
            for old, new in zip(self.committed, words)
        ):
            return count, True

        # Whisper sometimes revises words already typed. A time-qualified
        # match reanchors the remaining words without rewriting earlier text.
        last = self.committed[-1]
        alignment = [
            (abs(word.end - last.end), index)
            for index, word in enumerate(words)
            if word.key == last.key and abs(word.end - last.end) <= 0.28
        ]
        if alignment:
            return min(alignment)[1] + 1, True

        # If the anchor itself changed, skip words centered in committed audio.
        return next((i for i, word in enumerate(words)
                     if (word.start + word.end) / 2 >= last.end), len(words)), False

    def update(self, words, duration, final):
        offset, aligned = self.align(words)
        tail = words[offset:]
        punctuation = ""
        if final:
            if aligned and offset and self.committed:
                old = self.committed[-1].text.strip().casefold()
                new = words[offset - 1].text.strip().casefold()
                suffix = new[len(old):] if new.startswith(old) else ""
                if suffix and all(ch in ".,!?;:…" for ch in suffix):
                    punctuation = suffix
            return render_words(tail), "", punctuation

        stable = []
        if aligned:
            previous_offset, previous_aligned = self.align(self.previous)
            if previous_aligned:
                for old, new in zip(self.previous[previous_offset:], tail[:-1]):
                    if (old.key != new.key or abs(old.end - new.end) > 0.34
                            or min(old.probability, new.probability) < 0.38
                            or new.end > duration - 0.30):
                        break
                    text = new.text
                    if old.text.strip() != new.text.strip():
                        # A trailing period on an unfinished hypothesis can
                        # disappear as soon as another word is recognized.
                        text = text.rstrip(".,!?;:…") or text
                    stable.append(Word(text, new.start, new.end))
        self.previous = words
        self.committed.extend(stable)
        return render_words(stable), render_words(tail[len(stable):]), ""


def short_window_model(model_class, np):
    class ShortWindowModel(model_class):
        def encode(self, features):
            # faster-whisper zero-pads each encoder input to 30 seconds.
            # Leave enough silence for timestamp alignment while keeping
            # short interactive passes below the full training window.
            if features.ndim == 2:
                signal = np.flatnonzero(np.any(features, axis=0))
                if signal.size:
                    limit = max(800, (int(signal[-1]) + 208) // 8 * 8)
                    if limit < features.shape[-1]:
                        features = features[:, :limit]
            return super().encode(features)

    return ShortWindowModel


class Recognizer:
    """Only the inference thread accesses the model."""

    def __init__(self):
        self.key = None
        self.model = None
        self.executor = ThreadPoolExecutor(max_workers=1)

    def prepare(self, options):
        import ctranslate2
        import numpy as np
        from faster_whisper import WhisperModel

        key = (options["model"], options["device"])
        if self.key != key:
            self.key = None
            self.model = None
            self.device = "cpu"
            gpu_preferred = key[1] == "gpu" or (key[1] == "auto" and key[0] != "tiny")
            if gpu_preferred and self.has_cuda(ctranslate2):
                self.device = "cuda"
            self.model_type = short_window_model(WhisperModel, np)
            self.model = self.load(self.model_type, key[0], self.device)
            self.key = key

    def decode(self, pcm, options, speculative, language_hint=None):
        import numpy as np

        self.prepare(options)
        samples = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768
        language = options["language"] or language_hint
        duration = len(samples) / RATE

        def transcribe():
            segments, info = self.model.transcribe(
                samples, language=language,
                beam_size=1 if speculative else options["final_beam"], word_timestamps=True,
                max_new_tokens=max(24, int(duration * 15) + 8),
                temperature=0.0, condition_on_previous_text=False,
                log_prob_threshold=-0.9, compression_ratio_threshold=2.2,
                vad_filter=True,
                vad_parameters={"min_speech_duration_ms": 130, "min_silence_duration_ms": 350},
                hotwords=options["vocabulary"] or None,
                log_progress=False,
            )
            words = []
            for segment in segments:
                words.extend(
                    Word(word.word, float(word.start), float(word.end), float(word.probability))
                    for word in segment.words or () if word.end > word.start
                )
            return words, info.language, info.language_probability

        try:
            result = transcribe()
        except RuntimeError:
            if self.device != "cuda":
                raise
            self.model = None
            self.model = self.load(self.model_type, key[0], "cpu")
            result = transcribe()
        return (*result, self.device)

    @staticmethod
    def has_cuda(ctranslate2):
        try:
            if not ctranslate2.get_cuda_device_count():
                return False
            for library in ("libcublas.so.12", "libcudnn.so.9"):
                ctypes.CDLL(library)
            return "float16" in ctranslate2.get_supported_compute_types("cuda")
        except (OSError, RuntimeError, ValueError):
            return False

    def load(self, model_class, name, device):
        try:
            model = model_class(
                str(MODELS_DIR / name), device=device, local_files_only=True,
                compute_type="float16" if device == "cuda" else "int8",
                cpu_threads=min(6, len(os.sched_getaffinity(0))),
            )
        except (RuntimeError, ValueError):
            if device != "cuda":
                raise
            return self.load(model_class, name, "cpu")
        self.device = device
        return model


def options_from(request):
    def choose(name, valid, default):
        value = request.get(name)
        return value if isinstance(value, str) and value in valid else default

    behavior = choose("behavior", {"responsive", "balanced", "context"}, "balanced")
    pause, maximum, refresh = {
        "responsive": (400, 3400, 560), "balanced": (520, 4600, 680), "context": (740, 6400, 900),
    }[behavior]
    return {
        "model": choose("model", MODELS, "base"),
        "device": choose("device", {"auto", "cpu", "gpu"}, "auto"),
        "language": choose("language", {"ru", "en", "es", "ca"}, ""),
        "vocabulary": str(request.get("vocabulary") or "")[:300],
        "preview": request.get("preview") is True,
        "microphone": str(request.get("microphone") or "")[:512],
        "pause": pause, "maximum": maximum, "refresh": refresh // 20,
        "final_beam": 2 if behavior == "context" else 1,
    }


class Focus:
    def __init__(self, address):
        self.address = address if isinstance(address, str) else ""
        self.lost = asyncio.Event()

    async def check(self):
        code, out = await command("hyprctl", "-j", "activewindow")
        if code or self.lost.is_set():
            raise VoiceError("The original window lost focus")
        try:
            active = json.loads(out).get("address", "")
        except (ValueError, AttributeError):
            active = ""
        if str(active).lower() != self.address.lower() or self.lost.is_set():
            raise VoiceError("The original window lost focus")

    async def connect(self):
        path = (Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr"
                / os.environ["HYPRLAND_INSTANCE_SIGNATURE"] / ".socket2.sock")
        return await asyncio.wait_for(asyncio.open_unix_connection(path), 2)

    async def watch(self, reader):
        try:
            while event := await reader.readline():
                name, _, value = event.decode(errors="replace").strip().partition(">>")
                if name in {"activewindowv2", "closewindow"}:
                    address = value.lower().removeprefix("0x")
                    same = address == self.address.lower().removeprefix("0x")
                    if (name == "activewindowv2" and not same) or (name == "closewindow" and same):
                        break
                if name in {"lock", "sessionlock"}:
                    break
        finally:
            self.lost.set()

    async def insert(self, text):
        for offset in range(0, len(text), TEXT_FRAGMENT_SIZE):
            await self.check()
            fragment = text[offset:offset + TEXT_FRAGMENT_SIZE]
            code, _ = await command(str(TEXT_INPUT), payload=fragment.encode("utf-8"))
            if code:
                raise VoiceError("The focused window could not receive typed text")


async def microphone(name):
    if name:
        # wpctl inspect accepts numeric IDs. Resolve the saved stable PipeWire name.
        code, out = await command("pw-dump")
        if not code:
            for obj in json.loads(out):
                props = obj.get("info", {}).get("props", {})
                if props.get("node.name") == name and props.get("media.class", "").startswith("Audio/Source"):
                    return str(props["object.serial"])
        raise VoiceError("The selected microphone is unavailable")
    code, out = await command("wpctl", "inspect", "@DEFAULT_AUDIO_SOURCE@")
    match = re.search(rb'object\.serial\s*=\s*"(\d+)"', out)
    if code or not match:
        raise VoiceError("No default PipeWire microphone")
    return match[1].decode()


class Session:
    def __init__(self, request, recognizer):
        self.options = options_from(request)
        self.recognizer = recognizer
        self.focus = Focus(request.get("address"))
        self.stop = asyncio.Event()
        self.cancelled = False
        self.active_decode = False
        self.last_sample = 0
        self.current = 0
        self.queue = asyncio.Queue(maxsize=4)
        self.chunks = SpeechChunks(self.options["pause"], self.options["maximum"])
        self.inserted = False
        self.capture = None

    def finish(self):
        if not self.stop.is_set():
            self.stop.set()
            emit(state="finishing", level=0, preview="")

    async def monitor_source(self, serial):
        while True:
            await asyncio.sleep(2)
            if self.stop.is_set():
                continue
            code, out = await command("pw-dump")
            if code or not any(
                str(o.get("info", {}).get("props", {}).get("object.serial", "")) == serial
                for o in json.loads(out)
            ):
                raise VoiceError("The microphone disconnected")

    def enqueue(self, pcm):
        if not pcm:
            return
        sequence = self.current
        self.current += 1
        self.last_sample = 0
        emit(preview="")
        if self.queue.full():
            raise VoiceError("Transcription fell behind. Try a smaller model")
        self.queue.put_nowait((pcm, sequence, False))

    async def record(self, serial):
        self.capture = await asyncio.create_subprocess_exec(
            "setpriv", "--pdeathsig", "TERM", "pw-record", "--raw",
            "--rate", str(RATE), "--channels", "1", "--format", "s16",
            "--latency", "40ms", "--target", serial,
            "--properties", "{ node.dont-reconnect = true }", "-",
            stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        frames = 0
        stopping = asyncio.create_task(self.stop.wait())
        try:
            while not self.stop.is_set():
                pending = asyncio.create_task(self.capture.stdout.readexactly(FRAME_BYTES))
                try:
                    done, _ = await asyncio.wait({pending, stopping}, timeout=3,
                                                 return_when=asyncio.FIRST_COMPLETED)
                    if pending not in done:
                        if stopping in done:
                            break
                        raise VoiceError("No audio from the microphone")
                    pcm = pending.result()
                except asyncio.IncompleteReadError as error:
                    if self.stop.is_set():
                        break
                    raise VoiceError("Microphone capture stopped") from error
                finally:
                    if not pending.done():
                        pending.cancel()
                        await asyncio.gather(pending, return_exceptions=True)
                frames += 1
                if frames == 1 and not self.stop.is_set():
                    emit(state="listening")
                rms, chunk = self.chunks.feed(pcm)
                if frames % 2 == 0:
                    emit(level=min(1, rms ** 0.6 * 3.6))
                self.enqueue(chunk)
                # Streaming remains active when the visual preview is disabled.
                # Start another hypothesis only after enough new audio arrives.
                sample = len(self.chunks.frames)
                refresh = self.options["refresh"]
                if (not self.stop.is_set() and self.chunks.voiced >= 34 and self.chunks.quiet < 10
                        and sample - self.last_sample >= refresh
                        and not self.active_decode and self.queue.empty()):
                    self.last_sample = sample
                    self.queue.put_nowait((b"".join(self.chunks.frames), self.current, True))
        finally:
            stopping.cancel()
            if self.capture.returncode is None:
                self.capture.terminate()
                try:
                    await asyncio.wait_for(self.capture.communicate(), 1)
                except asyncio.TimeoutError:
                    self.capture.kill()
                    await self.capture.communicate()
        if not self.cancelled:
            self.enqueue(self.chunks.flush())
            await self.queue.put(None)

    async def transcribe(self):
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(self.recognizer.executor, self.recognizer.prepare, self.options)
        stream = StreamingText()
        previous_sequence = None
        language = None
        while (item := await self.queue.get()) is not None:
            pcm, sequence, speculative = item
            if speculative and (sequence != self.current or self.stop.is_set()):
                continue
            if speculative:
                # If loading the model delayed this job, use the latest audio
                # rather than first decoding a stale snapshot.
                self.last_sample = len(self.chunks.frames)
                pcm = b"".join(self.chunks.frames)
            if sequence != previous_sequence:
                stream = StreamingText()
                language = None
                previous_sequence = sequence
            self.active_decode = True
            try:
                words, detected, probability, device = await loop.run_in_executor(
                    self.recognizer.executor, self.recognizer.decode, pcm, self.options,
                    speculative, language,
                )
            finally:
                self.active_decode = False
            if self.cancelled or self.focus.lost.is_set():
                return
            if speculative and (sequence != self.current or self.stop.is_set()):
                continue
            if words and (self.options["language"] or (len(pcm) >= RATE * 2.5 and probability >= 0.65)):
                language = detected
            text, preview, punctuation = stream.update(
                words, len(pcm) / (RATE * 2), final=not speculative,
            )
            if text or punctuation:
                separator = " " if text and self.inserted else ""
                await self.focus.insert(punctuation + separator + text)
                self.inserted = True
            emit(
                state="transcribing" if speculative and preview and self.options["preview"] else "listening",
                preview=preview if self.options["preview"] else "",
                committed=text, language=detected, device=device,
            )

    async def run(self):
        tasks = []
        writer = None
        completion = None
        result = None
        try:
            if not re.fullmatch(r"0x[0-9a-fA-F]+", self.focus.address or ""):
                raise VoiceError("Focus a text field before dictating")
            if any(not shutil.which(program) for program in ("pw-record", "wpctl", "pw-dump", "setpriv")):
                raise VoiceError("PipeWire utilities are unavailable")
            from importlib.util import find_spec
            if find_spec("faster_whisper") is None:
                raise VoiceError("Install the local speech engine in Voice Typing settings")
            requested = self.options["model"]
            choices = (requested, "medium", "small", "base", "tiny") if requested == "large-v3-turbo" else (requested,)
            for name in choices:
                directory = MODELS_DIR / name
                files = REQUIRED_MODEL_FILES + (("preprocessor_config.json",) if name == "large-v3-turbo" else ())
                if all((directory / item).is_file() for item in files):
                    self.options["model"] = name
                    break
            else:
                raise VoiceError(f"Install the {requested} speech model in Voice Typing settings")
            if not os.access(TEXT_INPUT, os.X_OK):
                raise VoiceError("Run Voice Typing setup to install its keyboard helper")
            reader, writer = await self.focus.connect()
            watch = asyncio.create_task(self.focus.watch(reader))
            tasks.append(watch)
            await self.focus.check()
            code, _ = await command(str(TEXT_INPUT), "--probe")
            if code:
                raise VoiceError("Hyprland virtual keyboard access is unavailable")
            source = await microphone(self.options["microphone"])
            if self.cancelled:
                return
            capture = asyncio.create_task(self.record(source))
            decode = asyncio.create_task(self.transcribe())
            source_watch = asyncio.create_task(self.monitor_source(source))
            tasks.extend((capture, decode, source_watch))
            # Completing a dictation requires both capture shutdown and a full
            # drain of the recognizer and keyboard. Silence leaves both alive.
            completion = asyncio.gather(capture, decode)
            await asyncio.wait({completion, watch, source_watch}, return_when=asyncio.FIRST_COMPLETED)
            if self.focus.lost.is_set():
                raise VoiceError("Dictation stopped because focus changed")
            if source_watch.done():
                source_watch.result()
            await completion
            result = {"state": "success" if self.inserted else "empty"}
        except VoiceError as error:
            result = {"state": "error", "message": str(error)}
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            if isinstance(error, (RuntimeError, ImportError)):
                message = "The speech model could not run. Check the model or try CPU"
            else:
                message = "Could not finish dictation. Check the audio and desktop session"
            result = {"state": "error", "message": message}
        finally:
            for task in tasks:
                if not task.done():
                    task.cancel()
            if completion is not None:
                await asyncio.gather(completion, return_exceptions=True)
            await asyncio.gather(*tasks, return_exceptions=True)
            if writer:
                writer.close()
        if result is not None and not self.cancelled:
            emit(**result, level=0, preview="")


async def main():
    reader = asyncio.StreamReader(limit=8192)
    loop = asyncio.get_running_loop()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, reader.feed_eof)
    recognizer = Recognizer()
    session = task = None
    try:
        while line := await reader.readline():
            request = json.loads(line)
            action = request.get("action")
            if action == "quit":
                break
            if action == "start" and (task is None or task.done()):
                if task is not None:
                    task.result()
                session = Session(request, recognizer)
                task = asyncio.create_task(session.run())
            elif action == "cancel":
                if task and not task.done():
                    session.cancelled = True
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)
                session = task = None
                emit(state="idle", level=0, preview="")
            elif action == "stop" and task and not task.done():
                session.finish()
    finally:
        if task and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
    # A canceled native inference may still be on the executor. The microphone
    # has been released, and process exit drops both the model and audio buffers.
    os._exit(0)


if __name__ == "__main__":
    asyncio.run(main())
