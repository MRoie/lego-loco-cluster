#!/usr/bin/env python3
"""Teach PCem v17 to take pointer input from a remote (VNC) client.

PCem is built for someone sitting at the machine: the first left-click in the
SDL window calls SDL_SetWindowGrab + SDL_SetRelativeMouseMode, after which
mouse_poll_host() reads *relative* motion, and SDL keeps warping the host
pointer back to the window centre every frame.

That is exactly wrong for a headless Xvfb driven by x11vnc. The VNC client
sends *absolute* pointer positions, x11vnc replays them with XTest, and SDL's
warp-to-centre immediately fights every one of them — the guest cursor drifts,
and clicks land somewhere other than where the user aimed (this is the
"mouse clicks routinely fail to register" symptom recorded as gotcha #23 in
../standalone/README.md).

With PCEM_VNC_MOUSE=1 set in the environment, this patch:
  * never grabs the pointer and never enables relative mode,
  * derives guest mickeys from frame-to-frame deltas of the *absolute* host
    pointer position, so the guest cursor tracks the client's cursor and
    re-synchronises whenever both are pinned against a screen edge,
  * keeps the wheel working, and stops right-click from opening PCem's own
    wx popup menu over the guest.

Unset (or 0), PCem behaves exactly as upstream.

Usage: vnc-mouse.py <pcem-source-root>
"""

import pathlib
import sys

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

# --------------------------------------------------------------------------
# 1. wx-sdl2-mouse.c — absolute-position tracking as an alternative to
#    SDL's relative mode.
# --------------------------------------------------------------------------
MOUSE_OLD = """void mouse_poll_host()
{
        if (mousecapture)
        {"""

MOUSE_NEW = """/* Set by PCEM_VNC_MOUSE=1. See patches/vnc-mouse.py. */
int pcem_vnc_mouse()
{
        static int cached = -1;
        if (cached < 0)
        {
                const char *e = getenv("PCEM_VNC_MOUSE");
                cached = (e && *e && *e != '0') ? 1 : 0;
        }
        return cached;
}

static int pcem_env_int(const char *name, int fallback)
{
        const char *e = getenv(name);
        return (e && *e) ? atoi(e) : fallback;
}

/* PCEM_POINTER_MODE=absolute puts the guest cursor exactly where the remote
   client points, instead of nudging it by the client's motion. VNC, RDP and
   touch/tablet devices all report an ABSOLUTE position; a PS/2 or serial mouse
   can only report relative motion, so the two are reconciled by keeping a
   model of where the guest cursor is and emitting the packet that closes the
   gap. */
static int pcem_pointer_absolute()
{
        static int cached = -1;
        if (cached < 0)
        {
                const char *e = getenv("PCEM_POINTER_MODE");
                cached = (e && !strcmp(e, "absolute")) ? 1 : 0;
        }
        return cached;
}

static int pcem_mouse_debug()
{
        static int cached = -1;
        if (cached < 0)
                cached = pcem_env_int("PCEM_VNC_MOUSE_DEBUG", 0);
        return cached;
}

/* What the guest cursor actually does with a packet of `d` mickeys.

   Measured on the Windows 98 SE snapshot: a 2-mickey packet moves the cursor
   2 pixels, a 5-mickey packet moves it 10. So the guest doubles, the boundary
   sits somewhere in between, and it is *lower* than the MouseThreshold1 of 6
   the documentation promises. Rather than pin the boundary down we simply
   never emit a packet inside the uncertain band — see pcem_step_for().

   PCEM_MOUSE_SPEED=0 asserts the guest has acceleration switched off, making
   this the identity. */
static int pcem_guest_travel(int d)
{
        int creep = pcem_env_int("PCEM_MOUSE_CREEP", 2);
        int dmin = pcem_env_int("PCEM_MOUSE_DOUBLE_MIN", 8);
        int speed = pcem_env_int("PCEM_MOUSE_SPEED", 1);
        int magnitude = d < 0 ? -d : d;

        if (speed < 1)
                return d;
        if (magnitude <= creep)
                return d;
        if (magnitude >= dmin)
                return d * 2;
        /* Inside the uncertain band. pcem_step_for() does not emit here; if
           something else does, assume the worse case so the model does not
           silently run ahead of the guest. */
        return d * 2;
}

/* Choose the packet to emit for a desired displacement.

   The emulated serial mouse is the speed limit: mouse_serial_poll() writes a
   3-byte Microsoft packet straight into the UART FIFO, and the guest's driver
   reads it at the protocol's 1200 baud — order of 40 packets a second. Pixels
   per second is therefore pixels *per packet* times ~40, and creeping two
   pixels at a time works out at a uselessly slow ~100 px/s.

   So use the guest's own doubling for the distance and exact steps only for
   the last few pixels:

     |want| <= creep        emit it as-is; travels 1:1, lands exactly
     |want| <  2 * dmin     creep, because halving would land in the band
                            where we do not know whether the guest doubles
     otherwise              emit want/2 and let the guest double it

   Above 2*dmin that is one packet per ~250 pixels (max_packet is 120, and
   mouse_serial_poll clamps to +/-127), so a full-width sweep is a handful of
   packets, and the creep phase is bounded at 2*dmin/creep = 8 more. Roughly
   0.2s from anywhere to anywhere, against 8s for pure creeping.

   The tempting simplification — always halve — is what the previous version
   of this did, and it broke inside a game, where a cursor driven through
   DirectInput gets no acceleration and travels half as far as predicted. The
   creep band is what makes the endgame exact regardless: the final approach
   never relies on the guest doubling anything. */
static int pcem_step_for(int want)
{
        int creep = pcem_env_int("PCEM_MOUSE_CREEP", 2);
        int dmin = pcem_env_int("PCEM_MOUSE_DOUBLE_MIN", 8);
        int speed = pcem_env_int("PCEM_MOUSE_SPEED", 1);
        int max_packet = pcem_env_int("PCEM_MOUSE_MAX_PACKET", 120);
        int magnitude = want < 0 ? -want : want;
        int sign = want < 0 ? -1 : 1;
        int step;

        if (max_packet > 127)
                max_packet = 127;       /* mouse_serial_poll() clamps here */

        if (speed < 1)
        {
                /* No guest ballistics: a mickey is a pixel. */
                step = magnitude > max_packet ? max_packet : magnitude;
                return sign * step;
        }

        if (magnitude <= creep)
                return want;
        if (magnitude < 2 * dmin)
                return sign * creep;

        step = magnitude / 2;
        if (step > max_packet)
                step = max_packet;
        return sign * step;
}

extern SDL_Window *window;

/* The guest's own picture size, in guest pixels. With vid_resize=2 the SDL
   window is pinned to the VNC screen size and PCem stretches the guest
   framebuffer to fill it, so window pixels and guest pixels are no longer the
   same thing — the pointer model counts mickeys, which the guest measures in
   guest pixels. Everything below maps through this. */
extern void pcem_guest_size(int *w, int *h);

static void mouse_poll_host_pointer()
{
        /* Homing: the guest cursor's real position is unknown at startup, so
           drive it hard into the top-left corner. It clamps there whatever the
           acceleration settings are, which makes the model true. The same
           trick re-syncs automatically whenever the client parks the pointer
           against a screen edge. */
        static int home_polls = 40;
        static int model_x = 0, model_y = 0;
        static int last_w = 0, last_h = 0;
        static unsigned long polls = 0;

        int abs_x = 0, abs_y = 0;
        int win_x = 0, win_y = 0, win_w = 0, win_h = 0;
        int gw, gh;
        int want_x, want_y, step_x, step_y;
        uint32_t mb = SDL_GetGlobalMouseState(&abs_x, &abs_y);

        polls++;

        mouse_buttons = 0;
        if (mb & SDL_BUTTON(SDL_BUTTON_LEFT))
                mouse_buttons |= 1;
        if (mb & SDL_BUTTON(SDL_BUTTON_RIGHT))
                mouse_buttons |= 2;
        if (mb & SDL_BUTTON(SDL_BUTTON_MIDDLE))
                mouse_buttons |= 4;

        if (window)
        {
                SDL_GetWindowPosition(window, &win_x, &win_y);
                SDL_GetWindowSize(window, &win_w, &win_h);
        }
        if (win_w <= 0 || win_h <= 0)
                return;

        pcem_guest_size(&gw, &gh);
        if (gw <= 0) gw = win_w;
        if (gh <= 0) gh = win_h;

        /* A guest video-mode change moves the goalposts; the model is stale.
           Watch the guest size, not the window: under vid_resize=2 the window
           never changes and a 800x600 -> 640x480 switch would go unnoticed. */
        if (gw != last_w || gh != last_h)
        {
                last_w = gw;
                last_h = gh;
                home_polls = 40;
        }

        /* Window pixels -> guest pixels. Round to nearest so the far edge is
           reachable: with truncation the last window column maps a fraction
           short of gw-1 and the cursor can never quite touch the right edge. */
        want_x = win_w > 1 ? ((abs_x - win_x) * (gw - 1) + (win_w - 1) / 2) / (win_w - 1) : 0;
        want_y = win_h > 1 ? ((abs_y - win_y) * (gh - 1) + (win_h - 1) / 2) / (win_h - 1) : 0;
        if (want_x < 0) want_x = 0;
        if (want_y < 0) want_y = 0;
        if (want_x > gw - 1) want_x = gw - 1;
        if (want_y > gh - 1) want_y = gh - 1;

        if (home_polls > 0)
        {
                home_polls--;
                model_x = 0;
                model_y = 0;
                mouse[0] = -pcem_env_int("PCEM_MOUSE_MAX_PACKET", 100);
                mouse[1] = mouse[0];
        }
        else
        {
                /* Edge parking doubles as a free re-sync: push past the edge
                   and the guest pins where we say it does. */
                if (want_x <= 0)
                {
                        mouse[0] = -pcem_env_int("PCEM_MOUSE_MAX_PACKET", 100);
                        model_x = 0;
                }
                else if (want_x >= gw - 1)
                {
                        mouse[0] = pcem_env_int("PCEM_MOUSE_MAX_PACKET", 100);
                        model_x = gw - 1;
                }
                else
                {
                        step_x = pcem_step_for(want_x - model_x);
                        mouse[0] = step_x;
                        model_x += pcem_guest_travel(step_x);
                }

                if (want_y <= 0)
                {
                        mouse[1] = -pcem_env_int("PCEM_MOUSE_MAX_PACKET", 100);
                        model_y = 0;
                }
                else if (want_y >= gh - 1)
                {
                        mouse[1] = pcem_env_int("PCEM_MOUSE_MAX_PACKET", 100);
                        model_y = gh - 1;
                }
                else
                {
                        step_y = pcem_step_for(want_y - model_y);
                        mouse[1] = step_y;
                        model_y += pcem_guest_travel(step_y);
                }
        }

        if (pcem_mouse_debug() && (mouse[0] || mouse[1] || mb || pcem_mouse_debug() > 1))
        {
                fprintf(stderr,
                        "vncmouse#%lu abs=%d,%d win=%d,%d %dx%d guest=%dx%d want=%d,%d model=%d,%d step=%d,%d buttons=%08x home=%d\\n",
                        polls, abs_x, abs_y, win_x, win_y, win_w, win_h, gw, gh,
                        want_x, want_y, model_x, model_y,
                        mouse[0], mouse[1], (unsigned)mb, home_polls);
                fflush(stderr);
        }

        mouse_x += mouse[0];
        mouse_y += mouse[1];
        mouse_z += mouse[2];
        mouse[2] = 0;
}

static void mouse_poll_host_relative()
{
        static int have_last = 0;
        static int last_x = 0, last_y = 0;
        int abs_x = 0, abs_y = 0;
        uint32_t mb = SDL_GetGlobalMouseState(&abs_x, &abs_y);

        if (have_last)
        {
                mouse[0] = abs_x - last_x;
                mouse[1] = abs_y - last_y;
        }
        else
        {
                mouse[0] = mouse[1] = 0;
                have_last = 1;
        }
        last_x = abs_x;
        last_y = abs_y;

        mouse_buttons = 0;
        if (mb & SDL_BUTTON(SDL_BUTTON_LEFT))
                mouse_buttons |= 1;
        if (mb & SDL_BUTTON(SDL_BUTTON_RIGHT))
                mouse_buttons |= 2;
        if (mb & SDL_BUTTON(SDL_BUTTON_MIDDLE))
                mouse_buttons |= 4;

        mouse_x += mouse[0];
        mouse_y += mouse[1];
        mouse_z += mouse[2];
        mouse[2] = 0;
}

void mouse_poll_host()
{
        if (pcem_vnc_mouse())
        {
                if (pcem_pointer_absolute())
                        mouse_poll_host_pointer();
                else
                        mouse_poll_host_relative();
        }
        else if (mousecapture)
        {"""

# --------------------------------------------------------------------------
# 2. wx-sdl2-display.c — do not grab, do not warp, do not steal right-click.
# --------------------------------------------------------------------------
GRAB_OLD = """        if (window_doinputgrab) {
                window_doinputgrab = 0;
                mousecapture = 1;
                SDL_GetRelativeMouseState(0, 0);
                SDL_SetWindowGrab(window, SDL_TRUE);
                SDL_SetRelativeMouseMode(SDL_TRUE);
        }"""

GRAB_NEW = """        if (window_doinputgrab) {
                window_doinputgrab = 0;
                /* PCEM_VNC_MOUSE: a remote pointer must never be grabbed. */
                if (!pcem_vnc_mouse())
                {
                        mousecapture = 1;
                        SDL_GetRelativeMouseState(0, 0);
                        SDL_SetWindowGrab(window, SDL_TRUE);
                        SDL_SetRelativeMouseMode(SDL_TRUE);
                }
        }"""

CLICK_OLD = """                case SDL_MOUSEBUTTONUP:
                        if (!mousecapture)
                        {"""

CLICK_NEW = """                case SDL_MOUSEBUTTONUP:
                        /* PCEM_VNC_MOUSE: clicks belong to the guest, not to
                           PCem's click-to-capture / right-click menu. */
                        if (!mousecapture && !pcem_vnc_mouse())
                        {"""

WHEEL_OLD = """                        if (mousecapture) mouse_wheel_update(event.wheel.y);"""
WHEEL_NEW = """                        if (mousecapture || pcem_vnc_mouse()) mouse_wheel_update(event.wheel.y);"""

EXTERN_OLD = """extern void mouse_wheel_update(int);"""
EXTERN_NEW = """extern void mouse_wheel_update(int);
extern int pcem_vnc_mouse();"""

# --------------------------------------------------------------------------
# 3. wx-sdl2-video.c — expose the guest framebuffer size.
#
# The absolute-pointer model needs to know how big the guest's picture is, in
# guest pixels, so it can turn a client position in *window* pixels into the
# mickeys that put the guest cursor there. Once vid_resize=2 pins the window
# and PCem scales the guest to fill it, the two are different sizes.
#
# blit_rect is the only authoritative answer: it is set from what the video
# card actually blitted and is what sdl_renderer_present() scales. winsizex /
# winsizey look like the same thing and are not — they track the window, and
# under vid_resize=2 they keep their 640x480 initialiser forever.
# --------------------------------------------------------------------------
VIDEO_OLD = """int sdl_is_fullscreen(SDL_Window* window) {"""

VIDEO_NEW = """/* PCEM_VNC_MOUSE: guest framebuffer size, in guest pixels. */
void pcem_guest_size(int *w, int *h)
{
        *w = blit_rect.w;
        *h = blit_rect.h;
}

int sdl_is_fullscreen(SDL_Window* window) {"""

EDITS = [
    ("src/wx-sdl2-mouse.c", [(MOUSE_OLD, MOUSE_NEW)]),
    ("src/wx-sdl2-video.c", [(VIDEO_OLD, VIDEO_NEW)]),
    (
        "src/wx-sdl2-display.c",
        [
            (EXTERN_OLD, EXTERN_NEW),
            (GRAB_OLD, GRAB_NEW),
            (CLICK_OLD, CLICK_NEW),
            (WHEEL_OLD, WHEEL_NEW),
        ],
    ),
]


def main():
    for relpath, edits in EDITS:
        path = SRC / relpath
        text = path.read_text()
        for old, new in edits:
            count = text.count(old)
            if count != 1:
                sys.exit(
                    f"{relpath}: expected exactly 1 match for patch anchor, found {count}\n"
                    f"--- anchor ---\n{old}\n"
                    "PCem's source shape changed; re-derive this patch."
                )
            text = text.replace(old, new)
        path.write_text(text)
        print(f"patched {relpath}")

    # stdlib.h is already pulled in by string.h's transitive includes on glibc,
    # but getenv() deserves its own include rather than luck.
    mouse_c = SRC / "src/wx-sdl2-mouse.c"
    text = mouse_c.read_text()
    if "#include <stdlib.h>" not in text:
        text = text.replace(
            "#include <string.h>",
            "#include <string.h>\n#include <stdlib.h>\n#include <stdio.h>",
            1,
        )
        mouse_c.write_text(text)
        print("patched src/wx-sdl2-mouse.c (stdlib.h, stdio.h)")


if __name__ == "__main__":
    main()
