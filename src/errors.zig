//! SDL's error channel, narrowed to a Zig error union.
//!
//! SDL has no numeric error codes. Every failing call returns `false` or
//! `NULL` and leaves a description in a thread-local slot, so there is exactly
//! one error to return and one place to read the detail from.

const std = @import("std");
const raw = @import("sdl3_raw");

pub const Error = error{
    /// An SDL call failed. `lastErrorText` has the description SDL recorded
    /// for this thread.
    SdlError,
};

/// Turns SDL's `bool` return into an error union. Every wrapper that can fail
/// goes through here.
pub inline fn check(ok: bool) Error!void {
    if (!ok) return Error.SdlError;
}

/// The same for the calls that report failure with a null pointer.
pub inline fn checkPtr(pointer: anytype) Error!@TypeOf(pointer.?) {
    return pointer orelse Error.SdlError;
}

/// The description SDL recorded for the last failing call on this thread.
/// Borrowed from SDL and valid only until the next SDL call on this thread.
pub fn lastErrorText() []const u8 {
    const text = raw.SDL_GetError();
    if (text == null) return "no description";
    return std.mem.span(text);
}

/// SDL keeps the last error until it is overwritten, so a stale message can
/// outlive the call that produced it. Clear before a sequence you intend to
/// inspect.
pub fn clearError() void {
    _ = raw.SDL_ClearError();
}

/// Records an error as if an SDL call had failed. Useful in a callback that
/// SDL will read the error slot after.
pub fn setError(message: [:0]const u8) void {
    _ = raw.SDL_SetError("%s", message.ptr);
}
