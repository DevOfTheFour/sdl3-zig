//! Mouse state, cursors and pointer capture.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const rect_mod = @import("rect.zig");
const surface_mod = @import("surface.zig");
const video_mod = @import("video.zig");

const Error = errors.Error;
const check = errors.check;
const FPoint = rect_mod.FPoint;
const Surface = surface_mod.Surface;
const Window = video_mod.Window;

pub const MouseId = u32;

/// SDL numbers buttons from 1. `Button` keeps that numbering so a raw event's
/// `button` field converts with no arithmetic.
pub const Button = enum(u8) {
    left = raw.SDL_BUTTON_LEFT,
    middle = raw.SDL_BUTTON_MIDDLE,
    right = raw.SDL_BUTTON_RIGHT,
    /// "Back" on a mouse that has one.
    x1 = raw.SDL_BUTTON_X1,
    /// "Forward".
    x2 = raw.SDL_BUTTON_X2,
    _,
};

/// Which buttons are down, as named bits. Bit 0 is button 1, so this lines up
/// with `Button` shifted down by one.
pub const ButtonState = packed struct(u32) {
    left: bool = false,
    middle: bool = false,
    right: bool = false,
    x1: bool = false,
    x2: bool = false,
    _reserved: u27 = 0,

    pub const none: ButtonState = .{};

    pub fn isDown(self: ButtonState, button: Button) bool {
        const bit = @backingInt(button);
        if (bit == 0 or bit > 32) return false;
        return (@as(u32, @bitCast(self)) & (@as(u32, 1) << @intCast(bit - 1))) != 0;
    }
};

pub const WheelDirection = enum(c_uint) {
    normal = raw.SDL_MOUSEWHEEL_NORMAL,
    /// The platform has "natural" scrolling on: the deltas are negated
    /// relative to `normal`.
    flipped = raw.SDL_MOUSEWHEEL_FLIPPED,
    _,
};

pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
    buttons: ButtonState = .{},
};

pub fn hasMouse() bool {
    return raw.SDL_HasMouse();
}

/// Where the pointer is inside the focused window, and what is held.
pub fn state() Position {
    var result: Position = .{};
    result.buttons = @bitCast(raw.SDL_GetMouseState(&result.x, &result.y));
    return result;
}

/// Desktop coordinates rather than window ones.
pub fn globalState() Position {
    var result: Position = .{};
    result.buttons = @bitCast(raw.SDL_GetGlobalMouseState(&result.x, &result.y));
    return result;
}

/// Motion accumulated since the last call. This is the reading relative mode
/// exists for -- it keeps working when the pointer is against a screen edge.
pub fn relativeState() Position {
    var result: Position = .{};
    result.buttons = @bitCast(raw.SDL_GetRelativeMouseState(&result.x, &result.y));
    return result;
}

pub fn focusedWindow() ?Window {
    const handle = raw.SDL_GetMouseFocus() orelse return null;
    return .{ .handle = handle };
}

pub fn warpInWindow(window: Window, x: f32, y: f32) void {
    raw.SDL_WarpMouseInWindow(window.handle, x, y);
}

pub fn warpGlobal(x: f32, y: f32) Error!void {
    try check(raw.SDL_WarpMouseGlobal(x, y));
}

/// Keeps sending motion and button events after the pointer leaves the
/// window: what a drag that runs past the edge needs. Release it when the
/// drag ends.
pub fn setCapture(enabled: bool) Error!void {
    try check(raw.SDL_CaptureMouse(enabled));
}

pub fn showCursor() Error!void {
    try check(raw.SDL_ShowCursor());
}

pub fn hideCursor() Error!void {
    try check(raw.SDL_HideCursor());
}

pub fn cursorVisible() bool {
    return raw.SDL_CursorVisible();
}

pub const SystemCursor = enum(c_uint) {
    default = raw.SDL_SYSTEM_CURSOR_DEFAULT,
    text = raw.SDL_SYSTEM_CURSOR_TEXT,
    wait = raw.SDL_SYSTEM_CURSOR_WAIT,
    crosshair = raw.SDL_SYSTEM_CURSOR_CROSSHAIR,
    progress = raw.SDL_SYSTEM_CURSOR_PROGRESS,
    nwse_resize = raw.SDL_SYSTEM_CURSOR_NWSE_RESIZE,
    nesw_resize = raw.SDL_SYSTEM_CURSOR_NESW_RESIZE,
    ew_resize = raw.SDL_SYSTEM_CURSOR_EW_RESIZE,
    ns_resize = raw.SDL_SYSTEM_CURSOR_NS_RESIZE,
    move = raw.SDL_SYSTEM_CURSOR_MOVE,
    not_allowed = raw.SDL_SYSTEM_CURSOR_NOT_ALLOWED,
    /// The hand a link gets.
    pointer = raw.SDL_SYSTEM_CURSOR_POINTER,
    nw_resize = raw.SDL_SYSTEM_CURSOR_NW_RESIZE,
    n_resize = raw.SDL_SYSTEM_CURSOR_N_RESIZE,
    ne_resize = raw.SDL_SYSTEM_CURSOR_NE_RESIZE,
    e_resize = raw.SDL_SYSTEM_CURSOR_E_RESIZE,
    se_resize = raw.SDL_SYSTEM_CURSOR_SE_RESIZE,
    s_resize = raw.SDL_SYSTEM_CURSOR_S_RESIZE,
    sw_resize = raw.SDL_SYSTEM_CURSOR_SW_RESIZE,
    w_resize = raw.SDL_SYSTEM_CURSOR_W_RESIZE,
    _,
};

pub const Cursor = struct {
    handle: *raw.SDL_Cursor,

    pub fn initSystem(id: SystemCursor) Error!Cursor {
        return .{ .handle = try errors.checkPtr(raw.SDL_CreateSystemCursor(@backingInt(id))) };
    }

    /// A cursor from an image. `hot_x`, `hot_y` is the pixel inside the image
    /// that actually points at things.
    pub fn initColor(image: *Surface, hot_x: i32, hot_y: i32) Error!Cursor {
        const handle = raw.SDL_CreateColorCursor(@ptrCast(image), hot_x, hot_y);
        return .{ .handle = try errors.checkPtr(handle) };
    }

    pub fn deinit(self: Cursor) void {
        raw.SDL_DestroyCursor(self.handle);
    }

    /// Makes this the active cursor. It must outlive the assignment -- SDL
    /// keeps the pointer, not a copy.
    pub fn set(self: Cursor) Error!void {
        try check(raw.SDL_SetCursor(self.handle));
    }

    pub fn active() ?Cursor {
        const handle = raw.SDL_GetCursor() orelse return null;
        return .{ .handle = handle };
    }

    /// Owned by SDL; never call `deinit` on it.
    pub fn default() ?Cursor {
        const handle = raw.SDL_GetDefaultCursor() orelse return null;
        return .{ .handle = handle };
    }
};
