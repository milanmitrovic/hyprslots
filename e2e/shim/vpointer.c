// A pointer for the nested e2e Hyprland: moves to a point and clicks there,
// through wlr-virtual-pointer-unstable-v1, so the editor smoke drives the
// panel with real pointer events (the same MouseArea handlers a mouse
// reaches), as wtype drives it with real keys.
//
//   vpointer <x> <y> <width> <height> [move|click|double]
//
// x and y are in the layout's pixels; width and height its extent (one
// output here, at 0,0). The protocol's interfaces are spelled out below as
// wayland-scanner would write them (the XML is not installed on the host);
// request order and signatures follow wlr-virtual-pointer-unstable-v1.
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>

#define BTN_LEFT 0x110

extern const struct wl_interface zwlr_virtual_pointer_v1_interface;

static const struct wl_interface *types[] = {
    NULL, NULL, NULL, NULL, NULL,
    &wl_seat_interface, &zwlr_virtual_pointer_v1_interface,
};

static const struct wl_message manager_requests[] = {
    {"create_virtual_pointer", "?on", types + 5},
    {"destroy", "", types + 0},
};

static const struct wl_interface manager_interface = {
    "zwlr_virtual_pointer_manager_v1", 1, 2, manager_requests, 0, NULL,
};

static const struct wl_message pointer_requests[] = {
    {"motion", "uff", types + 0},
    {"motion_absolute", "uuuuu", types + 0},
    {"button", "uuu", types + 0},
    {"axis", "uuf", types + 0},
    {"frame", "", types + 0},
    {"axis_source", "u", types + 0},
    {"axis_stop", "uu", types + 0},
    {"axis_discrete", "uufi", types + 0},
    {"destroy", "", types + 0},
};

const struct wl_interface zwlr_virtual_pointer_v1_interface = {
    "zwlr_virtual_pointer_v1", 1, 9, pointer_requests, 0, NULL,
};

enum { MOTION_ABSOLUTE = 1, BUTTON = 2, FRAME = 4, DESTROY = 8 };

static struct wl_seat *seat;
static struct wl_proxy *manager;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                   uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, "wl_seat") == 0 && !seat) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    } else if (strcmp(interface, manager_interface.name) == 0) {
        manager = wl_registry_bind(registry, name, &manager_interface, 1);
    }
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {global, global_remove};

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void pause_ms(long ms) {
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000};
    nanosleep(&ts, NULL);
}

static void button(struct wl_display *display, struct wl_proxy *pointer, uint32_t state) {
    wl_proxy_marshal_flags(pointer, BUTTON, NULL, 1, 0, now_ms(), BTN_LEFT, state);
    wl_proxy_marshal_flags(pointer, FRAME, NULL, 1, 0);
    wl_display_roundtrip(display);
}

static void click(struct wl_display *display, struct wl_proxy *pointer) {
    button(display, pointer, 1);
    pause_ms(50);
    button(display, pointer, 0);
}

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "usage: %s <x> <y> <width> <height> [move|click|double]\n", argv[0]);
        return 2;
    }
    uint32_t x = (uint32_t)atoi(argv[1]), y = (uint32_t)atoi(argv[2]);
    uint32_t width = (uint32_t)atoi(argv[3]), height = (uint32_t)atoi(argv[4]);
    const char *action = argc > 5 ? argv[5] : "click";

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "vpointer: cannot connect to the Wayland display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) {
        fprintf(stderr, "vpointer: the compositor offers no zwlr_virtual_pointer_manager_v1\n");
        return 1;
    }

    struct wl_proxy *pointer = wl_proxy_marshal_flags(manager, 0, &zwlr_virtual_pointer_v1_interface, 1, 0,
                                                      (struct wl_proxy *)seat, NULL);
    wl_display_roundtrip(display);

    // Up to the point in two steps, then a pause: the compositor gives the
    // surface under it pointer focus before the button comes.
    wl_proxy_marshal_flags(pointer, MOTION_ABSOLUTE, NULL, 1, 0, now_ms(), x > 0 ? x - 1 : x + 1, y, width, height);
    wl_proxy_marshal_flags(pointer, FRAME, NULL, 1, 0);
    wl_display_roundtrip(display);
    pause_ms(40);
    wl_proxy_marshal_flags(pointer, MOTION_ABSOLUTE, NULL, 1, 0, now_ms(), x, y, width, height);
    wl_proxy_marshal_flags(pointer, FRAME, NULL, 1, 0);
    wl_display_roundtrip(display);
    pause_ms(200);

    if (strcmp(action, "click") == 0) {
        click(display, pointer);
    } else if (strcmp(action, "double") == 0) {
        click(display, pointer);
        pause_ms(80);
        click(display, pointer);
    } else if (strcmp(action, "move") != 0) {
        fprintf(stderr, "vpointer: unknown action %s\n", action);
        return 2;
    }
    pause_ms(300);

    wl_proxy_marshal_flags(pointer, DESTROY, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
