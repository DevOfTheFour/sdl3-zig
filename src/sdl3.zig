//! Zig bindings for [SDL 3](https://github.com/libsdl-org/SDL).
//!
//! SDL is C, so the raw layer is `translate-c` over `SDL.h` with no shim in
//! between. Everything else is the layer you are meant to use:
//!
//! - handles with `init` / `deinit` instead of create/destroy pairs;
//! - one `Error` set, because SDL has one error channel and no codes;
//! - `enum` for scancodes, buttons and formats instead of loose integers;
//! - `packed struct` for the flag words instead of or-ed constants;
//! - a `union(enum)` `Event`, where SDL has a C union and a separate tag.
//!
//! Reach for `raw` where the wrapper does not yet cover something.
//!
//! ```zig
//! try sdl.init(.{ .video = true });
//! defer sdl.quit();
//!
//! const both = try sdl.createWindowAndRenderer("app", 960, 540, .{});
//! defer both.renderer.deinit();
//! defer both.window.deinit();
//!
//! main: while (true) {
//!     while (sdl.events.poll()) |event| {
//!         if (event.isQuitFor(both.window.id())) break :main;
//!     }
//!     try both.renderer.setDrawColor(.rgb(20, 22, 30));
//!     try both.renderer.clear();
//!     try both.renderer.present();
//! }
//! ```

const std = @import("std");
const build_options = @import("sdl3_build_options");

/// Complete, mechanically translated SDL 3 API.
pub const raw = @import("sdl3_raw");

pub const errors = @import("errors.zig");
pub const rect = @import("rect.zig");
pub const pixels = @import("pixels.zig");
pub const surface = @import("surface.zig");
pub const properties = @import("properties.zig");
pub const video = @import("video.zig");
pub const render = @import("render.zig");
pub const keyboard = @import("keyboard.zig");
pub const mouse = @import("mouse.zig");
pub const gamepad = @import("gamepad.zig");
pub const events = @import("events.zig");
pub const audio = @import("audio.zig");
pub const timer = @import("timer.zig");
pub const hints = @import("hints.zig");
pub const log = @import("log.zig");
pub const io = @import("io.zig");
pub const filesystem = @import("filesystem.zig");

/// SDL's Vulkan surface helpers, compiled in with `-Dvulkan`. Without that
/// flag this namespace holds only `enabled = false`.
pub const vulkan = @import("vulkan.zig").module;

pub const features: Features = .{ .vulkan = build_options.vulkan };

pub const Features = struct {
    vulkan: bool,
};

// The types you reach for most, re-exported so a program can say
// `sdl.Window` rather than `sdl.video.Window`.
pub const Error = errors.Error;
pub const lastErrorText = errors.lastErrorText;
pub const clearError = errors.clearError;

pub const Point = rect.Point;
pub const FPoint = rect.FPoint;
pub const Rect = rect.Rect;
pub const FRect = rect.FRect;
pub const Size = rect.Size;

pub const Color = pixels.Color;
pub const FColor = pixels.FColor;
pub const PixelFormat = pixels.PixelFormat;
pub const BlendMode = pixels.BlendMode;
pub const ScaleMode = pixels.ScaleMode;
pub const FlipMode = pixels.FlipMode;

pub const Surface = surface.Surface;
pub const Properties = properties.Properties;

pub const Window = video.Window;
pub const WindowFlags = video.WindowFlags;
pub const Display = video.Display;
pub const DisplayMode = video.DisplayMode;

pub const Renderer = render.Renderer;
pub const Texture = render.Texture;
pub const Vertex = render.Vertex;
pub const createWindowAndRenderer = render.createWindowAndRenderer;

pub const Event = events.Event;
pub const EventType = events.EventType;

pub const Scancode = keyboard.Scancode;
pub const Keycode = keyboard.Keycode;
pub const KeyMod = keyboard.KeyMod;

pub const Gamepad = gamepad.Gamepad;

const check = errors.check;

// ---------------------------------------------------------------------
// Library lifetime
// ---------------------------------------------------------------------

/// Which subsystems to start. `events` comes along with `video`, `joystick`
/// and `gamepad`, and `gamepad` implies `joystick`, so the flags you actually
/// have to name are fewer than they look.
pub const InitFlags = packed struct(u32) {
    _reserved0: u4 = 0,
    audio: bool = false,
    video: bool = false,
    _reserved1: u3 = 0,
    joystick: bool = false,
    _reserved2: u2 = 0,
    haptic: bool = false,
    gamepad: bool = false,
    events: bool = false,
    sensor: bool = false,
    camera: bool = false,
    _reserved3: u15 = 0,
};

/// Starts the named subsystems. Safe to call more than once: SDL reference-
/// counts each subsystem, so a second `init` needs a second `quit`.
pub fn init(flags: InitFlags) Error!void {
    try check(raw.SDL_Init(@bitCast(flags)));
}

/// Starts more subsystems on top of what is already running.
pub fn initSubSystem(flags: InitFlags) Error!void {
    try check(raw.SDL_InitSubSystem(@bitCast(flags)));
}

pub fn quitSubSystem(flags: InitFlags) void {
    raw.SDL_QuitSubSystem(@bitCast(flags));
}

/// Which of the asked-for subsystems are running.
pub fn wasInit(flags: InitFlags) InitFlags {
    return @bitCast(raw.SDL_WasInit(@bitCast(flags)));
}

/// Shuts everything down, whatever the reference counts say. Call it once, at
/// the end, and let `deinit`s run before it.
pub fn quit() void {
    raw.SDL_Quit();
}

/// Names the application for the OS: the window manager, the audio mixer, and
/// the "this app wants to..." prompts all read it. Set it before `init`.
///
/// `identifier` is a reverse-DNS string such as "com.example.game".
pub fn setAppMetadata(
    name: [:0]const u8,
    version_string: [:0]const u8,
    identifier: [:0]const u8,
) Error!void {
    try check(raw.SDL_SetAppMetadata(name.ptr, version_string.ptr, identifier.ptr));
}

// ---------------------------------------------------------------------
// Version and platform
// ---------------------------------------------------------------------

pub const Version = struct {
    major: u32,
    minor: u32,
    micro: u32,

    pub fn format(self: Version, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.micro });
    }
};

/// The version of the SDL that is actually linked in, which for this package
/// is the one it built from source.
pub fn version() Version {
    const packed_version: u32 = @intCast(raw.SDL_GetVersion());
    return .{
        .major = packed_version / 1_000_000,
        .minor = (packed_version / 1_000) % 1_000,
        .micro = packed_version % 1_000,
    };
}

/// SDL's source revision string. Owned by SDL.
pub fn revision() []const u8 {
    const text = raw.SDL_GetRevision();
    if (text == null) return "";
    return std.mem.span(text);
}

/// "macOS", "Windows", "Linux", "iOS", "Android", "Emscripten". Owned by SDL.
pub fn platform() []const u8 {
    const text = raw.SDL_GetPlatform();
    if (text == null) return "";
    return std.mem.span(text);
}

pub fn logicalCpuCores() u32 {
    const count = raw.SDL_GetNumLogicalCPUCores();
    return if (count < 0) 0 else @intCast(count);
}

/// Total system memory in MiB.
pub fn systemRam() u32 {
    const mb = raw.SDL_GetSystemRAM();
    return if (mb < 0) 0 else @intCast(mb);
}

pub const PowerInfo = struct {
    state: gamepad.PowerState,
    /// Seconds of battery left, when the platform will say.
    seconds: ?u32,
    /// 0..100, when the platform will say.
    percent: ?u8,
};

pub fn powerInfo() PowerInfo {
    var seconds: c_int = -1;
    var percent: c_int = -1;
    const state = raw.SDL_GetPowerInfo(&seconds, &percent);
    return .{
        .state = @fromBackingInt(@intCast(state)),
        .seconds = if (seconds < 0) null else @intCast(seconds),
        .percent = if (percent < 0) null else @intCast(percent),
    };
}

// ---------------------------------------------------------------------
// Clipboard and shell
// ---------------------------------------------------------------------

pub fn hasClipboardText() bool {
    return raw.SDL_HasClipboardText();
}

/// SDL-allocated: free it with `freeClipboardText`.
pub fn clipboardText() Error![:0]u8 {
    const text = raw.SDL_GetClipboardText();
    if (text == null) return Error.SdlError;
    return std.mem.span(@as([*:0]u8, @ptrCast(text)));
}

pub fn freeClipboardText(text: [:0]u8) void {
    raw.SDL_free(text.ptr);
}

pub fn setClipboardText(text: [:0]const u8) Error!void {
    try check(raw.SDL_SetClipboardText(text.ptr));
}

/// Hands a URL to the platform's browser or handler. Works on "file://" too,
/// which is how you reveal a save directory to the user.
pub fn openUrl(url: [:0]const u8) Error!void {
    try check(raw.SDL_OpenURL(url.ptr));
}

/// Frees memory SDL allocated. Needed only where a call's documentation says
/// so; the wrappers that return SDL-owned memory each have their own `free`.
pub fn free(memory: ?*anyopaque) void {
    raw.SDL_free(memory);
}
pub const gpu = @import("gpu.zig");
