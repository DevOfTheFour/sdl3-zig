//! SDL's logging, which is also where SDL's own diagnostics come out.
//!
//! Worth routing somewhere you can see: when a renderer or an audio device
//! fails for a reason the return value cannot express, the explanation is
//! here.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");

const Error = errors.Error;
const check = errors.check;

pub const Priority = enum(c_uint) {
    invalid = raw.SDL_LOG_PRIORITY_INVALID,
    trace = raw.SDL_LOG_PRIORITY_TRACE,
    verbose = raw.SDL_LOG_PRIORITY_VERBOSE,
    debug = raw.SDL_LOG_PRIORITY_DEBUG,
    info = raw.SDL_LOG_PRIORITY_INFO,
    warn = raw.SDL_LOG_PRIORITY_WARN,
    err = raw.SDL_LOG_PRIORITY_ERROR,
    critical = raw.SDL_LOG_PRIORITY_CRITICAL,
    _,
};

/// SDL's own messages are filed under the category they came from, so
/// raising `video` alone is how you debug a windowing problem without
/// drowning in audio.
pub const Category = enum(c_int) {
    application = raw.SDL_LOG_CATEGORY_APPLICATION,
    err = raw.SDL_LOG_CATEGORY_ERROR,
    assert = raw.SDL_LOG_CATEGORY_ASSERT,
    system = raw.SDL_LOG_CATEGORY_SYSTEM,
    audio = raw.SDL_LOG_CATEGORY_AUDIO,
    video = raw.SDL_LOG_CATEGORY_VIDEO,
    render = raw.SDL_LOG_CATEGORY_RENDER,
    input = raw.SDL_LOG_CATEGORY_INPUT,
    _test = raw.SDL_LOG_CATEGORY_TEST,
    gpu = raw.SDL_LOG_CATEGORY_GPU,
    /// The first id an application may use for its own categories.
    custom = raw.SDL_LOG_CATEGORY_CUSTOM,
    _,
};

/// The longest message `messageFmt` will emit. Anything past this is cut.
pub const max_formatted_len = 1024;

pub fn setAllPriorities(priority: Priority) void {
    raw.SDL_SetLogPriorities(@backingInt(priority));
}

pub fn setPriority(category: Category, priority: Priority) void {
    raw.SDL_SetLogPriority(@backingInt(category), @backingInt(priority));
}

pub fn priorityOf(category: Category) Priority {
    return @fromBackingInt(@intCast(raw.SDL_GetLogPriority(@backingInt(category))));
}

/// The message goes through SDL's `%s`, so a `%` in `text` is not a format
/// directive and needs no escaping.
pub fn message(category: Category, level: Priority, text: [:0]const u8) void {
    raw.SDL_LogMessage(@backingInt(category), @backingInt(level), "%s", text.ptr);
}

/// Zig-side formatting, into a stack buffer of `max_formatted_len` bytes. A
/// message that does not fit is truncated rather than dropped.
pub fn messageFmt(
    category: Category,
    level: Priority,
    comptime fmt: []const u8,
    args: anytype,
) void {
    // One byte is held back for the terminator SDL's `%s` needs. On overflow
    // the writer keeps what it managed to write, which is the truncation.
    var buffer: [max_formatted_len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(buffer[0 .. buffer.len - 1]);
    writer.print(fmt, args) catch {};

    const written = writer.buffered().len;
    buffer[written] = 0;
    message(category, level, buffer[0..written :0]);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    messageFmt(.application, .info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    messageFmt(.application, .warn, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    messageFmt(.application, .err, fmt, args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    messageFmt(.application, .debug, fmt, args);
}

pub fn critical(comptime fmt: []const u8, args: anytype) void {
    messageFmt(.application, .critical, fmt, args);
}

pub const OutputFunction = *const fn (
    userdata: ?*anyopaque,
    category: c_int,
    level: Priority,
    text: [*c]const u8,
) callconv(.c) void;

/// Replaces SDL's own output, which is stderr on most platforms and the
/// debugger console on Windows. The function runs on whichever thread logged,
/// so it must be safe to call from any of them.
pub fn setOutputFunction(callback: OutputFunction, userdata: ?*anyopaque) void {
    raw.SDL_SetLogOutputFunction(@ptrCast(callback), userdata);
}
