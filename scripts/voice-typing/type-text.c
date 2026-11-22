#define _GNU_SOURCE
#include <linux/input-event-codes.h>
#include <locale.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wchar.h>
#include <wctype.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "virtual-keyboard.h"

enum { MAX_TEXT = 40 };

// Hyprland can resolve shortcuts by physical keycode even when the client
// installs a custom keymap. Use only printable physical keys.
static const uint32_t printable[] = {
    KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
    KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P,
    KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L,
    KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M,
    KEY_COMMA, KEY_DOT, KEY_SLASH, KEY_SPACE,
};

struct globals {
    struct wl_seat *seat;
    struct zwp_virtual_keyboard_manager_v1 *manager;
};

static void bind_global(void *data, struct wl_registry *registry, uint32_t name,
                        const char *interface, uint32_t version)
{
    struct globals *globals = data;
    (void)version;
    if (!globals->seat && strcmp(interface, wl_seat_interface.name) == 0)
        globals->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    if (!globals->manager && strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0)
        globals->manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
}

static void remove_global(void *data, struct wl_registry *registry, uint32_t name)
{
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = bind_global,
    .global_remove = remove_global,
};

static uint32_t clock_ms(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)(now.tv_sec * 1000ULL + now.tv_nsec / 1000000);
}

static int read_symbols(xkb_keysym_t symbols[MAX_TEXT])
{
    // One request fits in a small pipe write and carries no shell arguments.
    char utf8[MAX_TEXT * 4 + 1];
    size_t bytes = fread(utf8, 1, sizeof utf8, stdin);
    if (ferror(stdin) || bytes == sizeof utf8)
        return -1;
    if (!setlocale(LC_CTYPE, "C.UTF-8"))
        return -1;
    mbstate_t state = {0};
    int count = 0;
    for (size_t offset = 0; offset < bytes;) {
        wchar_t character;
        size_t used = mbrtowc(&character, utf8 + offset, bytes - offset, &state);
        if (used == (size_t)-1 || used == (size_t)-2 || !used || count == MAX_TEXT
            || iswcntrl(character))
            return -1;
        symbols[count] = xkb_utf32_to_keysym((uint32_t)character);
        if (symbols[count] == XKB_KEY_NoSymbol)
            return -1;
        ++count;
        offset += used;
    }
    return count;
}

static uint32_t write_keymap(FILE *file, const xkb_keysym_t *symbols, int count)
{
    fputs("xkb_keymap { xkb_keycodes { minimum=8; maximum=255;\n", file);
    fprintf(file, "<ARM>=%d;\n", KEY_LEFTSHIFT + 8);
    for (int i = 0; i < count; ++i)
        fprintf(file, "<K%02d>=%u;\n", i, printable[i] + 8);

    fputs("}; xkb_types { type \"ONE_LEVEL\" { modifiers=None; level_name[Level1]=\"Any\"; }; };\n"
          "xkb_compatibility {}; xkb_symbols {\n"
          "key <ARM> { type=\"ONE_LEVEL\", [ Shift_L ] };\n", file);
    for (int i = 0; i < count; ++i) {
        char name[64];
        if (xkb_keysym_get_name(symbols[i], name, sizeof name) <= 0)
            return 0;
        fprintf(file, "key <K%02d> { type=\"ONE_LEVEL\", [ %s ] };\n", i, name);
    }
    fputs("}; };", file);
    if (fputc(0, file) == EOF || fflush(file) == EOF)
        return 0;
    long length = ftell(file);
    return length > 0 ? (uint32_t)length : 0;
}

static bool send_key(struct wl_display *display, struct zwp_virtual_keyboard_v1 *keyboard,
                     uint32_t key)
{
    zwp_virtual_keyboard_v1_key(keyboard, clock_ms(), key, WL_KEYBOARD_KEY_STATE_PRESSED);
    if (wl_display_roundtrip(display) < 0)
        return false;
    zwp_virtual_keyboard_v1_key(keyboard, clock_ms(), key, WL_KEYBOARD_KEY_STATE_RELEASED);
    return wl_display_roundtrip(display) >= 0;
}

static bool type_symbols(struct wl_display *display, const struct globals *globals,
                         const xkb_keysym_t *symbols, int count)
{
    int fd = memfd_create("caelestia-voice-keymap", MFD_CLOEXEC);
    if (fd < 0)
        return false;
    FILE *file = fdopen(fd, "w+");
    if (!file) {
        close(fd);
        return false;
    }
    uint32_t length = write_keymap(file, symbols, count);
    if (!length) {
        fclose(file);
        return false;
    }
    rewind(file);
    struct zwp_virtual_keyboard_v1 *keyboard =
        zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(globals->manager, globals->seat);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, length);
    fclose(file);

    zwp_virtual_keyboard_v1_modifiers(keyboard, 0, 0, 0, 0);
    bool ok = wl_display_roundtrip(display) >= 0;
    // Some clients drop the key that activates a newly created keyboard.
    // Prime it with Shift, which also has no text in the physical keymap.
    if (ok)
        ok = send_key(display, keyboard, KEY_LEFTSHIFT);
    if (ok)
        usleep(24000);
    for (int i = 0; i < count && ok; ++i) {
        ok = send_key(display, keyboard, printable[i]);
        usleep(3000);
    }
    zwp_virtual_keyboard_v1_destroy(keyboard);
    return ok && wl_display_roundtrip(display) >= 0;
}

int main(int argc, char **argv)
{
    bool probe = argc == 2 && strcmp(argv[1], "--probe") == 0;
    xkb_keysym_t symbols[MAX_TEXT];
    int count = probe ? 0 : read_symbols(symbols);
    if (count < 0 || (argc != 1 && !probe)) {
        fputs("Invalid Voice Typing input\n", stderr);
        return 2;
    }

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fputs("Cannot connect to Wayland\n", stderr);
        return 3;
    }
    struct globals globals = {0};
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, &globals);
    bool ok = wl_display_roundtrip(display) >= 0 && globals.manager && globals.seat;
    if (ok && count)
        ok = type_symbols(display, &globals, symbols, count);
    if (globals.seat)
        wl_seat_destroy(globals.seat);
    if (globals.manager)
        zwp_virtual_keyboard_manager_v1_destroy(globals.manager);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    if (!ok)
        fputs("Wayland virtual keyboard is unavailable\n", stderr);
    return ok ? 0 : 3;
}
