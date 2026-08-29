//! SDL's configuration knobs.
//!
//! Hints are string key-value pairs SDL reads at various points. Most only
//! take effect if they are set *before* the subsystem they affect is
//! initialised, which is why they usually go at the very top of `main`.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");

const Error = errors.Error;
const check = errors.check;

pub const Priority = enum(c_uint) {
    /// Loses to an environment variable.
    default = raw.SDL_HINT_DEFAULT,
    normal = raw.SDL_HINT_NORMAL,
    /// Wins over an environment variable.
    override = raw.SDL_HINT_OVERRIDE,
    _,
};

pub fn set(hint: [:0]const u8, value: [:0]const u8) Error!void {
    try check(raw.SDL_SetHint(hint.ptr, value.ptr));
}

pub fn setWithPriority(hint: [:0]const u8, value: [:0]const u8, priority: Priority) Error!void {
    try check(raw.SDL_SetHintWithPriority(hint.ptr, value.ptr, @backingInt(priority)));
}

/// Null when the hint has never been set and has no environment override.
/// Borrowed from SDL.
pub fn get(hint: [:0]const u8) ?[]const u8 {
    const value = raw.SDL_GetHint(hint.ptr);
    if (value == null) return null;
    return std.mem.span(value);
}

/// SDL's own truthiness rules: "1", "true" and "yes" are true.
pub fn getBool(hint: [:0]const u8, default_value: bool) bool {
    return raw.SDL_GetHintBoolean(hint.ptr, default_value);
}

pub fn reset(hint: [:0]const u8) Error!void {
    try check(raw.SDL_ResetHint(hint.ptr));
}

pub fn resetAll() void {
    raw.SDL_ResetHints();
}

/// A few hints worth knowing by name. `sdl.raw` has the rest -- every
/// `SDL_HINT_*` string constant is there.
pub const names = struct {
    /// Set to "0" to keep the compositor from being disabled on X11.
    pub const video_x11_net_wm_bypass_compositor: [:0]const u8 = raw.SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR;
    /// Which renderer backends to try, in order: "vulkan,opengl,software".
    pub const render_driver: [:0]const u8 = raw.SDL_HINT_RENDER_DRIVER;
    /// Which video backend to use: "wayland,x11" on Linux, "dummy" for a
    /// headless run.
    pub const video_driver: [:0]const u8 = raw.SDL_HINT_VIDEO_DRIVER;
    /// "1" keeps events flowing while the window is in the background.
    pub const joystick_allow_background_events: [:0]const u8 = raw.SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS;
    /// "0" stops SDL from installing its own SIGINT and SIGTERM handlers.
    pub const no_signal_handlers: [:0]const u8 = raw.SDL_HINT_NO_SIGNAL_HANDLERS;
    /// "1" keeps the screen saver enabled while the application runs.
    pub const video_allow_screensaver: [:0]const u8 = raw.SDL_HINT_VIDEO_ALLOW_SCREENSAVER;
    /// Where the mouse sits after relative mode is turned off.
    pub const mouse_relative_mode_center: [:0]const u8 = raw.SDL_HINT_MOUSE_RELATIVE_MODE_CENTER;
};
