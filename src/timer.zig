//! Clocks, sleeping, and SDL's own timer thread.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");

const Error = errors.Error;
const check = errors.check;

/// Milliseconds since `sdl.init`, from a monotonic clock.
pub fn ticks() u64 {
    return raw.SDL_GetTicks();
}

/// The same clock in nanoseconds. Event timestamps are on this scale.
pub fn ticksNs() u64 {
    return raw.SDL_GetTicksNS();
}

/// The platform's highest-resolution counter. Divide a difference by
/// `performanceFrequency` for seconds. This is what a profiler wants; `ticks`
/// is what a game loop wants.
pub fn performanceCounter() u64 {
    return raw.SDL_GetPerformanceCounter();
}

pub fn performanceFrequency() u64 {
    return raw.SDL_GetPerformanceFrequency();
}

/// Seconds between two `performanceCounter` readings.
pub fn secondsBetween(start: u64, end: u64) f64 {
    const freq: f64 = @floatFromInt(performanceFrequency());
    return @as(f64, @floatFromInt(end -% start)) / freq;
}

/// Sleeps at least this long. The OS decides how much longer.
pub fn delay(ms: u32) void {
    raw.SDL_Delay(ms);
}

pub fn delayNs(ns: u64) void {
    raw.SDL_DelayNS(ns);
}

/// Busy-waits the last stretch to land closer to the requested time, at the
/// cost of burning CPU. For frame pacing, not for idling.
pub fn delayPrecise(ns: u64) void {
    raw.SDL_DelayPrecise(ns);
}

/// A repeating callback on SDL's own timer thread.
///
/// The callback does not run on the thread that added it, so everything it
/// touches must be safe to touch from another thread. Returning 0 stops the
/// timer; any other value is the next interval, which is how a one-shot or a
/// changing period is written.
pub const Timer = struct {
    id: u32,

    pub const Callback = *const fn (userdata: ?*anyopaque, id: u32, interval_ms: u32) callconv(.c) u32;

    pub fn init(interval_ms: u32, callback: Callback, userdata: ?*anyopaque) Error!Timer {
        const id = raw.SDL_AddTimer(interval_ms, callback, userdata);
        if (id == 0) return Error.SdlError;
        return .{ .id = id };
    }

    /// Blocks until a callback already in flight has returned, so it is safe
    /// to free the userdata straight after this.
    pub fn deinit(self: Timer) Error!void {
        try check(raw.SDL_RemoveTimer(self.id));
    }
};
