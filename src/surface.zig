//! CPU-side pixel buffers: what BMP and PNG files load into, what a window
//! icon is made of, and what the software renderer draws to.
//!
//! `Surface` is SDL's own struct, not a handle wrapping it, so `surface.w` and
//! `surface.pixels` read straight from SDL's memory. It is reference-counted:
//! handing one to something that keeps it (a window icon, a palette owner)
//! does not stop `deinit` from being correct.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const pixels_mod = @import("pixels.zig");
const rect_mod = @import("rect.zig");
const io_mod = @import("io.zig");

const Error = errors.Error;
const check = errors.check;
const Color = pixels_mod.Color;
const PixelFormat = pixels_mod.PixelFormat;
const Palette = pixels_mod.Palette;
const BlendMode = pixels_mod.BlendMode;
const ScaleMode = pixels_mod.ScaleMode;
const FlipMode = pixels_mod.FlipMode;
const Rect = rect_mod.Rect;

pub const SurfaceFlags = packed struct(u32) {
    /// The pixels belong to the caller, not to SDL.
    preallocated: bool = false,
    /// `lock` must be called before touching `pixels`.
    lock_needed: bool = false,
    locked: bool = false,
    simd_aligned: bool = false,
    _reserved: u28 = 0,
};

/// A CPU-side image. Layout-compatible with `SDL_Surface`.
pub const Surface = extern struct {
    flags: SurfaceFlags,
    format: PixelFormat,
    w: c_int,
    h: c_int,
    /// Bytes per row, which is not always `w * bytesPerPixel`.
    pitch: c_int,
    pixels: ?*anyopaque,
    refcount: c_int,
    reserved: ?*anyopaque,

    /// A new surface with SDL-owned, zeroed pixels.
    pub fn init(width: i32, height: i32, format: PixelFormat) Error!*Surface {
        const handle = raw.SDL_CreateSurface(width, height, @backingInt(format));
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, handle)));
    }

    /// A surface over memory the caller owns. The pixels must outlive the
    /// surface -- SDL neither copies nor frees them.
    pub fn initFromPixels(
        width: i32,
        height: i32,
        format: PixelFormat,
        buffer: []u8,
        pitch: usize,
    ) Error!*Surface {
        std.debug.assert(buffer.len >= pitch * @as(usize, @intCast(height)));
        const handle = raw.SDL_CreateSurfaceFrom(
            width,
            height,
            @backingInt(format),
            buffer.ptr,
            @intCast(pitch),
        );
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, handle)));
    }

    pub fn loadBmp(path: [:0]const u8) Error!*Surface {
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, raw.SDL_LoadBMP(path.ptr))));
    }

    /// Loads from an already-open stream: a BMP embedded in an archive, or
    /// one already in memory. `close_stream` hands the stream to SDL to
    /// close, whether the load succeeds or not.
    pub fn loadBmpFromStream(stream: io_mod.IOStream, close_stream: bool) Error!*Surface {
        const handle = raw.SDL_LoadBMP_IO(stream.handle, close_stream);
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, handle)));
    }

    /// Drops one reference. The surface is freed when the last one goes.
    pub fn deinit(self: *Surface) void {
        raw.SDL_DestroySurface(@ptrCast(self));
    }

    pub fn size(self: *const Surface) rect_mod.Size {
        return .{ .width = self.w, .height = self.h };
    }

    pub fn saveBmp(self: *Surface, path: [:0]const u8) Error!void {
        try check(raw.SDL_SaveBMP(@ptrCast(self), path.ptr));
    }

    /// SDL 3.4 writes PNG without a third-party image library.
    pub fn savePng(self: *Surface, path: [:0]const u8) Error!void {
        try check(raw.SDL_SavePNG(@ptrCast(self), path.ptr));
    }

    /// Writes into a stream rather than a path -- a dynamic-memory stream is
    /// how you get an encoded image into a buffer.
    pub fn savePngToStream(
        self: *Surface,
        stream: io_mod.IOStream,
        close_stream: bool,
    ) Error!void {
        try check(raw.SDL_SavePNG_IO(@ptrCast(self), stream.handle, close_stream));
    }

    // -- pixels ---------------------------------------------------------

    /// True when `pixels` must not be touched outside a `lock`/`unlock` pair.
    /// RLE-encoded surfaces are the common case.
    pub fn mustLock(self: *const Surface) bool {
        return self.flags.lock_needed;
    }

    /// Makes `pixels` safe to read and write. Always pair with `unlock`,
    /// even when `mustLock` is false.
    pub fn lock(self: *Surface) Error!void {
        try check(raw.SDL_LockSurface(@ptrCast(self)));
    }

    pub fn unlock(self: *Surface) void {
        raw.SDL_UnlockSurface(@ptrCast(self));
    }

    /// The raw bytes, `pitch * h` of them. Null before a `lock` on a surface
    /// that needs one.
    pub fn pixelBytes(self: *Surface) ?[]u8 {
        const base: [*]u8 = @ptrCast(self.pixels orelse return null);
        return base[0 .. @as(usize, @intCast(self.pitch)) * @as(usize, @intCast(self.h))];
    }

    /// One pixel, unpacked. Slow by design -- for a whole image, lock and walk
    /// `pixelBytes` instead.
    pub fn readPixel(self: *Surface, x: i32, y: i32) Error!Color {
        var color: Color = .{};
        try check(raw.SDL_ReadSurfacePixel(
            @ptrCast(self),
            x,
            y,
            &color.r,
            &color.g,
            &color.b,
            &color.a,
        ));
        return color;
    }

    pub fn writePixel(self: *Surface, x: i32, y: i32, color: Color) Error!void {
        try check(raw.SDL_WriteSurfacePixel(
            @ptrCast(self),
            x,
            y,
            color.r,
            color.g,
            color.b,
            color.a,
        ));
    }

    /// Packs a colour into this surface's format, for `fillRect`.
    pub fn mapColor(self: *Surface, color: Color) u32 {
        return raw.SDL_MapSurfaceRGBA(@ptrCast(self), color.r, color.g, color.b, color.a);
    }

    // -- drawing --------------------------------------------------------

    /// Overwrites the whole surface, ignoring the clip rect and blend mode.
    pub fn clear(self: *Surface, color: pixels_mod.FColor) Error!void {
        try check(raw.SDL_ClearSurface(@ptrCast(self), color.r, color.g, color.b, color.a));
    }

    /// Fills `area`, or the whole surface when null. `color` is a packed
    /// pixel value from `mapColor`.
    pub fn fillRect(self: *Surface, area: ?Rect, color: u32) Error!void {
        const ptr: [*c]const raw.SDL_Rect = if (area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_FillSurfaceRect(@ptrCast(self), ptr, color));
    }

    /// Copies `src_area` of `src` to `dst_area` of this surface. A null area
    /// means the whole surface; a `dst_area` larger than `src_area` does not
    /// scale -- use `blitScaled` for that.
    pub fn blitFrom(
        self: *Surface,
        src: *Surface,
        src_area: ?Rect,
        dst_area: ?Rect,
    ) Error!void {
        const src_ptr: [*c]const raw.SDL_Rect = if (src_area) |r| @ptrCast(&r) else null;
        const dst_ptr: [*c]const raw.SDL_Rect = if (dst_area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_BlitSurface(@ptrCast(src), src_ptr, @ptrCast(self), dst_ptr));
    }

    pub fn blitScaledFrom(
        self: *Surface,
        src: *Surface,
        src_area: ?Rect,
        dst_area: ?Rect,
        scale_mode: ScaleMode,
    ) Error!void {
        const src_ptr: [*c]const raw.SDL_Rect = if (src_area) |r| @ptrCast(&r) else null;
        const dst_ptr: [*c]const raw.SDL_Rect = if (dst_area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_BlitSurfaceScaled(
            @ptrCast(src),
            src_ptr,
            @ptrCast(self),
            dst_ptr,
            @backingInt(scale_mode),
        ));
    }

    // -- transforms; each returns a new surface the caller owns -----------

    pub fn duplicate(self: *Surface) Error!*Surface {
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, raw.SDL_DuplicateSurface(@ptrCast(self)))));
    }

    pub fn convert(self: *Surface, format: PixelFormat) Error!*Surface {
        const handle = raw.SDL_ConvertSurface(@ptrCast(self), @backingInt(format));
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, handle)));
    }

    pub fn scaled(self: *Surface, width: i32, height: i32, mode: ScaleMode) Error!*Surface {
        const handle = raw.SDL_ScaleSurface(@ptrCast(self), width, height, @backingInt(mode));
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, handle)));
    }

    /// In place, unlike the other transforms.
    pub fn flip(self: *Surface, mode: FlipMode) Error!void {
        try check(raw.SDL_FlipSurface(@ptrCast(self), @backingInt(mode)));
    }

    // -- appearance -----------------------------------------------------

    pub fn setBlendMode(self: *Surface, mode: BlendMode) Error!void {
        try check(raw.SDL_SetSurfaceBlendMode(@ptrCast(self), @backingInt(mode)));
    }

    pub fn blendMode(self: *Surface) Error!BlendMode {
        var mode: raw.SDL_BlendMode = 0;
        try check(raw.SDL_GetSurfaceBlendMode(@ptrCast(self), &mode));
        return @fromBackingInt(@intCast(mode));
    }

    pub fn setColorMod(self: *Surface, r: u8, g: u8, b: u8) Error!void {
        try check(raw.SDL_SetSurfaceColorMod(@ptrCast(self), r, g, b));
    }

    pub fn setAlphaMod(self: *Surface, alpha: u8) Error!void {
        try check(raw.SDL_SetSurfaceAlphaMod(@ptrCast(self), alpha));
    }

    /// Makes pixels matching `key` (a packed value from `mapColor`)
    /// transparent when this surface is blitted. Pass null to clear it.
    pub fn setColorKey(self: *Surface, key: ?u32) Error!void {
        try check(raw.SDL_SetSurfaceColorKey(@ptrCast(self), key != null, key orelse 0));
    }

    pub fn setClipRect(self: *Surface, area: ?Rect) Error!void {
        const ptr: [*c]const raw.SDL_Rect = if (area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_SetSurfaceClipRect(@ptrCast(self), ptr));
    }

    pub fn setPalette(self: *Surface, new_palette: *Palette) Error!void {
        try check(raw.SDL_SetSurfacePalette(@ptrCast(self), @ptrCast(new_palette)));
    }

    /// Null for a surface with no indexed format.
    pub fn palette(self: *Surface) ?*Palette {
        return @ptrCast(raw.SDL_GetSurfacePalette(@ptrCast(self)));
    }
};

comptime {
    std.debug.assert(@sizeOf(Surface) == @sizeOf(raw.SDL_Surface));
    std.debug.assert(@offsetOf(Surface, "pixels") == @offsetOf(raw.SDL_Surface, "pixels"));
}
