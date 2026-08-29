//! Points and rectangles, in both the integer and float flavours SDL uses.
//!
//! SDL's own `SDL_Rect` and `SDL_FRect` are already plain structs, so these
//! are layout-compatible with them and passed straight through. What they add
//! is the handful of geometry helpers SDL exposes as free functions.

const std = @import("std");
const raw = @import("sdl3_raw");

pub const Point = extern struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn toFloat(self: Point) FPoint {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    }

    pub fn inRect(self: Point, rect: Rect) bool {
        return raw.SDL_PointInRect(@ptrCast(&self), @ptrCast(&rect));
    }
};

pub const FPoint = extern struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn inRect(self: FPoint, rect: FRect) bool {
        return raw.SDL_PointInRectFloat(@ptrCast(&self), @ptrCast(&rect));
    }
};

/// A rectangle in integer coordinates: `x`, `y` is the top-left corner.
pub const Rect = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,

    pub fn isEmpty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }

    pub fn toFloat(self: Rect) FRect {
        return .{
            .x = @floatFromInt(self.x),
            .y = @floatFromInt(self.y),
            .w = @floatFromInt(self.w),
            .h = @floatFromInt(self.h),
        };
    }

    pub fn equals(self: Rect, other: Rect) bool {
        return raw.SDL_RectsEqual(@ptrCast(&self), @ptrCast(&other));
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return raw.SDL_HasRectIntersection(@ptrCast(&self), @ptrCast(&other));
    }

    /// The overlapping area, or null when the two do not touch.
    pub fn intersection(self: Rect, other: Rect) ?Rect {
        var result: Rect = .{};
        if (!raw.SDL_GetRectIntersection(@ptrCast(&self), @ptrCast(&other), @ptrCast(&result))) return null;
        return result;
    }

    /// The smallest rectangle containing both.
    pub fn unionWith(self: Rect, other: Rect) Rect {
        var result: Rect = .{};
        _ = raw.SDL_GetRectUnion(@ptrCast(&self), @ptrCast(&other), @ptrCast(&result));
        return result;
    }

    /// The smallest rectangle enclosing every point, ignoring points outside
    /// `clip` when one is given. Null when nothing was enclosed.
    pub fn enclosingPoints(points: []const Point, clip: ?Rect) ?Rect {
        var result: Rect = .{};
        const clip_ptr: [*c]const raw.SDL_Rect = if (clip) |c| @ptrCast(&c) else null;
        if (!raw.SDL_GetRectEnclosingPoints(
            @ptrCast(points.ptr),
            @intCast(points.len),
            clip_ptr,
            @ptrCast(&result),
        )) return null;
        return result;
    }
};

/// A rectangle in float coordinates. This is what the 2D renderer draws with.
pub const FRect = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn isEmpty(self: FRect) bool {
        return self.w <= 0 or self.h <= 0;
    }

    pub fn equals(self: FRect, other: FRect) bool {
        return raw.SDL_RectsEqualFloat(@ptrCast(&self), @ptrCast(&other));
    }

    pub fn intersects(self: FRect, other: FRect) bool {
        return raw.SDL_HasRectIntersectionFloat(@ptrCast(&self), @ptrCast(&other));
    }

    pub fn intersection(self: FRect, other: FRect) ?FRect {
        var result: FRect = .{};
        if (!raw.SDL_GetRectIntersectionFloat(@ptrCast(&self), @ptrCast(&other), @ptrCast(&result))) return null;
        return result;
    }

    pub fn unionWith(self: FRect, other: FRect) FRect {
        var result: FRect = .{};
        _ = raw.SDL_GetRectUnionFloat(@ptrCast(&self), @ptrCast(&other), @ptrCast(&result));
        return result;
    }
};

/// A width and height with no origin. Returned by everything that asks SDL
/// how big something is.
pub const Size = struct {
    width: i32 = 0,
    height: i32 = 0,
};

pub const FSize = struct {
    width: f32 = 0,
    height: f32 = 0,
};

comptime {
    // These are handed to SDL by pointer, so a layout mismatch would be a
    // silent memory bug rather than a compile error.
    std.debug.assert(@sizeOf(Point) == @sizeOf(raw.SDL_Point));
    std.debug.assert(@sizeOf(FPoint) == @sizeOf(raw.SDL_FPoint));
    std.debug.assert(@sizeOf(Rect) == @sizeOf(raw.SDL_Rect));
    std.debug.assert(@sizeOf(FRect) == @sizeOf(raw.SDL_FRect));
}
