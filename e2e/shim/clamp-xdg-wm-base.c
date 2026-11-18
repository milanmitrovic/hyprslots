// LD_PRELOAD shim for the nested e2e Hyprland: clamp its xdg_wm_base bind to
// the version the sway host advertises.
//
// aquamarine 0.15.1's Wayland backend binds xdg_wm_base at version 6
// unconditionally; sway 1.12 (wlroots) advertises version 5, so the host
// kills the connection with "invalid version for global xdg_wm_base".
// Version 6 only adds the xdg_toplevel `suspended` state (no new requests),
// so binding at 5 is safe. Every other request is forwarded unchanged.
//
// wl_registry_bind is an inline wrapper around the variadic
// wl_proxy_marshal_flags, so that is what we interpose; the arguments are
// rebuilt from the message signature and passed to the public
// wl_proxy_marshal_array_flags.
#define _GNU_SOURCE
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <wayland-client-core.h>
#include <wayland-util.h>

#define HOST_XDG_WM_BASE_VERSION 5
#define MAX_ARGS 20

// struct wl_proxy starts with struct wl_object, whose first member is the
// proxy's interface. libwayland has kept that layout since 1.0.
static const struct wl_interface *proxy_interface(struct wl_proxy *proxy) {
    return *(const struct wl_interface **)proxy;
}

struct wl_proxy *wl_proxy_marshal_flags(struct wl_proxy *proxy, uint32_t opcode, const struct wl_interface *interface,
                                        uint32_t version, uint32_t flags, ...) {
    const struct wl_interface *self = proxy_interface(proxy);
    const char *signature = self->methods[opcode].signature;
    union wl_argument args[MAX_ARGS];
    int count = 0;

    va_list ap;
    va_start(ap, flags);
    for (const char *c = signature; *c && count < MAX_ARGS; c++) {
        switch (*c) {
            case 'i': args[count++].i = va_arg(ap, int32_t); break;
            case 'u': args[count++].u = va_arg(ap, uint32_t); break;
            case 'f': args[count++].f = va_arg(ap, wl_fixed_t); break;
            case 's': args[count++].s = va_arg(ap, const char *); break;
            case 'o': args[count++].o = va_arg(ap, struct wl_object *); break;
            case 'n': args[count++].o = va_arg(ap, struct wl_object *); break;
            case 'a': args[count++].a = va_arg(ap, struct wl_array *); break;
            case 'h': args[count++].h = va_arg(ap, int32_t); break;
            default: break; // '?' nullability markers and since-version digits
        }
    }
    va_end(ap);

    // wl_registry.bind: signature "usun" = name, interface name, version, new_id.
    if (opcode == 0 && strcmp(self->name, "wl_registry") == 0 && interface && strcmp(interface->name, "xdg_wm_base") == 0 &&
        version > HOST_XDG_WM_BASE_VERSION) {
        version = HOST_XDG_WM_BASE_VERSION;
        args[2].u = HOST_XDG_WM_BASE_VERSION;
    }

    return wl_proxy_marshal_array_flags(proxy, opcode, interface, version, flags, args);
}
