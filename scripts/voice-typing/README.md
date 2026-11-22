# Caelestia Voice Typing

The settings are under **Nexus → Services → Voice Typing**. Select **Large v3 Turbo** and click **Install selected model** for the one-time engine and model download. Appearance preferences apply live. Capture and recognition settings are read at the start of each dictation.

1. Focus the text field where you want the words to appear.
2. Press **Ctrl + Super + V** and speak. Nexus checks the configured shortcut against live Hyprland bindings.
3. Press the same shortcut again or press **Esc** to finish and insert the remaining speech. Esc also reaches the active application.

## Local setup

Install `python3`, `uv`, `flock`, `setpriv`, and the PipeWire tools `pw-record`, `pw-dump` and `wpctl`. Setup builds the keyboard helper with `cc`, `pkg-config`, `wayland-scanner` and the Wayland and xkbcommon development headers. Setup uses an isolated Python 3.13 environment and stores the models under `${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/voice-typing`. With network access, the settings action is equivalent to the following command from the shell configuration's root directory.

```sh
bash scripts/voice-typing/setup.sh large-v3-turbo
```

Use **Auto** for automatic language detection or select Russian, English, Spanish or Catalan/Valencian. Vocabulary hints can help with names and technical terms. Large v3 Turbo is the recommended multilingual model. If it is still downloading, the worker can use an already-installed Medium, Small, Base or Tiny model. Language detection runs on each phrase. Code-switching within a phrase depends on the model.

CPU uses INT8. Auto prefers NVIDIA CUDA for Base and larger models when CUDA 12 cuBLAS and cuDNN 9 are present. **Prefer NVIDIA GPU** also tries Tiny on CUDA. The installer adds the optional CUDA libraries to this feature's environment when an NVIDIA GPU is available and CPU-only processing is disabled. If CUDA is unavailable, the worker uses CPU. To install the libraries separately:

```sh
uv pip install --python "${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/voice-typing/venv/bin/python" \
    nvidia-cublas-cu12 'nvidia-cudnn-cu12>=9,<10'
```

## Integration

The Quickshell service stores preferences in `caelestia/voice-typing.json` under the XDG configuration directory. It owns the worker through JSON lines on stdin and stdout. The worker opens PipeWire on demand, tracks the original Hyprland window and holds the engine warm for three idle minutes. Shell reload, cancellation or exit closes capture. Audio and transcripts are held in memory during operation.

The waveform reads RMS from the actual PCM stream. An adaptive amplitude gate identifies possible phrase boundaries, and Silero VAD filters the candidate audio. During continuous speech the worker re-decodes the current phrase as audio arrives. When consecutive decodes agree on earlier words, it types those words immediately and leaves the uncertain tail in the overlay. A short pause or the duration limit commits the remaining text of that phrase and leaves the widget listening. Pressing the stop shortcut keeps the widget visible until capture ends and pending text has been inserted. Streaming insertion also runs when the overlay preview is off.

Responsive, Balanced and More context request another decode after about 560 ms, 680 ms and 900 ms of new audio respectively, when the worker is free. These profiles close a phrase after roughly 400 ms, 520 ms or 740 ms of silence. Recognition latency includes model warm-up and inference. Short phrases use bounded CTranslate2 encoder input to avoid processing 30 seconds of padding on every pass.

## Appearance and themes

Open **Nexus → Services → Voice Typing → Appearance / Theme**. The preview cards use the real theme components with static sample text and audio levels. The selector saves appearance independently of capture, recognition and text insertion. Changing themes leaves the current worker and audio stream running while the original app keeps focus.

- `classic` is the recovered two-line pill, labeled **Default · Classic** in Settings. The earliest original inline widget source was unavailable, so this entry comes from the earliest recoverable pill design.
- `compact` is the recovered single-row pill.
- `dynamic-wave` is the wallpaper-colored floating wave. Speech raises the wave from the microphone outward, with a faster attack and a slower decay. During processing the wave settles into a ring around the microphone. It remains the default for configurations without a saved theme.

Position, scale and animation speed are shared. Transcription preview and live waveform settings are saved per theme and initially inherit the existing preferences.

Treat each redesign as a new theme unless an existing theme is explicitly being edited. Keep existing theme IDs and assets available. Register new visuals in `modules/voicetyping/ThemeRegistry.qml` with a stable ID, dimensions and a component derived from `ThemeWidget`. The component reads visual inputs from `ThemePresentation`. The widget can double as the preview or supply a specialized preview component. Preview presentations contain only sample data. A theme can supply an options component and persist its visual settings through `VoiceTyping.setThemeOption`.

The Dynamic Wave shader is in `modules/voicetyping/dynamic-wave-ribbons.frag`. Rebuild its asset with `/usr/lib/qt6/bin/qsb --qt6 -o dynamic-wave-ribbons.frag.qsb dynamic-wave-ribbons.frag` from that directory.

Typing uses a small Wayland virtual-keyboard helper. It accepts UTF-8 through a private pipe, applies the keymap before sending the first character, and uses printable keycodes so virtual typing cannot trigger Escape. The clipboard is untouched. The worker verifies application-window focus before each fragment and cancels on Hyprland focus or window-close events. Hyprland cannot identify individual text fields within a window, so keep the cursor in the intended field while dictating. A compositor focus change can still race an in-flight key event. Application handling of virtual keyboard Unicode can vary, especially under XWayland.

To diagnose settings or shortcut issues:

```sh
qs -c caelestia ipc call voiceTyping status
```
