//! Pixel formats, colours, palettes and blend modes.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const Error = errors.Error;
const check = errors.check;

/// An 8-bit-per-channel colour. Layout-compatible with `SDL_Color`.
pub const Color = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };
    pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };
    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toFloat(self: Color) FColor {
        return .{
            .r = @as(f32, @floatFromInt(self.r)) / 255.0,
            .g = @as(f32, @floatFromInt(self.g)) / 255.0,
            .b = @as(f32, @floatFromInt(self.b)) / 255.0,
            .a = @as(f32, @floatFromInt(self.a)) / 255.0,
        };
    }
};

/// A colour in the 0..1 float range the renderer works in internally.
pub const FColor = extern struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 1,
};

/// How a draw is combined with what is already in the target.
///
/// Non-exhaustive because `composeCustom` mints values outside this list.
pub const BlendMode = enum(u32) {
    none = raw.SDL_BLENDMODE_NONE,
    /// Straight alpha: the usual choice for sprites with transparency.
    blend = raw.SDL_BLENDMODE_BLEND,
    blend_premultiplied = raw.SDL_BLENDMODE_BLEND_PREMULTIPLIED,
    add = raw.SDL_BLENDMODE_ADD,
    add_premultiplied = raw.SDL_BLENDMODE_ADD_PREMULTIPLIED,
    mod = raw.SDL_BLENDMODE_MOD,
    mul = raw.SDL_BLENDMODE_MUL,
    invalid = raw.SDL_BLENDMODE_INVALID,
    _,

    /// Builds a blend mode out of SDL's factors and operations. Not every
    /// backend supports every combination; a draw with an unsupported mode
    /// fails rather than falling back.
    pub fn composeCustom(
        src_color: BlendFactor,
        dst_color: BlendFactor,
        color_op: BlendOperation,
        src_alpha: BlendFactor,
        dst_alpha: BlendFactor,
        alpha_op: BlendOperation,
    ) BlendMode {
        return @fromBackingInt(@intCast(raw.SDL_ComposeCustomBlendMode(
            @backingInt(src_color),
            @backingInt(dst_color),
            @backingInt(color_op),
            @backingInt(src_alpha),
            @backingInt(dst_alpha),
            @backingInt(alpha_op),
        )));
    }
};

pub const BlendFactor = enum(c_uint) {
    zero = raw.SDL_BLENDFACTOR_ZERO,
    one = raw.SDL_BLENDFACTOR_ONE,
    src_color = raw.SDL_BLENDFACTOR_SRC_COLOR,
    one_minus_src_color = raw.SDL_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
    src_alpha = raw.SDL_BLENDFACTOR_SRC_ALPHA,
    one_minus_src_alpha = raw.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    dst_color = raw.SDL_BLENDFACTOR_DST_COLOR,
    one_minus_dst_color = raw.SDL_BLENDFACTOR_ONE_MINUS_DST_COLOR,
    dst_alpha = raw.SDL_BLENDFACTOR_DST_ALPHA,
    one_minus_dst_alpha = raw.SDL_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
    _,
};

pub const BlendOperation = enum(c_uint) {
    add = raw.SDL_BLENDOPERATION_ADD,
    subtract = raw.SDL_BLENDOPERATION_SUBTRACT,
    rev_subtract = raw.SDL_BLENDOPERATION_REV_SUBTRACT,
    minimum = raw.SDL_BLENDOPERATION_MINIMUM,
    maximum = raw.SDL_BLENDOPERATION_MAXIMUM,
    _,
};

/// How a texture is sampled when it is drawn at a size other than its own.
pub const ScaleMode = enum(c_int) {
    invalid = raw.SDL_SCALEMODE_INVALID,
    /// Nearest-neighbour: what pixel art wants.
    nearest = raw.SDL_SCALEMODE_NEAREST,
    linear = raw.SDL_SCALEMODE_LINEAR,
    pixelart = raw.SDL_SCALEMODE_PIXELART,
    _,
};

pub const FlipMode = enum(c_uint) {
    none = raw.SDL_FLIP_NONE,
    horizontal = raw.SDL_FLIP_HORIZONTAL,
    vertical = raw.SDL_FLIP_VERTICAL,
    horizontal_and_vertical = raw.SDL_FLIP_HORIZONTAL_AND_VERTICAL,
    _,
};

/// Every pixel layout SDL names.
///
/// The channel order in these names is the order in memory for the byte-array
/// formats (`rgb24`) and the order within a machine word for the packed ones
/// (`argb8888`), which is why `rgba32` is a different format on a big-endian
/// machine. Use the endian-independent aliases below when you are writing
/// bytes yourself.
pub const PixelFormat = enum(c_uint) {
    unknown = raw.SDL_PIXELFORMAT_UNKNOWN,
    index1lsb = raw.SDL_PIXELFORMAT_INDEX1LSB,
    index1msb = raw.SDL_PIXELFORMAT_INDEX1MSB,
    index2lsb = raw.SDL_PIXELFORMAT_INDEX2LSB,
    index2msb = raw.SDL_PIXELFORMAT_INDEX2MSB,
    index4lsb = raw.SDL_PIXELFORMAT_INDEX4LSB,
    index4msb = raw.SDL_PIXELFORMAT_INDEX4MSB,
    index8 = raw.SDL_PIXELFORMAT_INDEX8,
    rgb332 = raw.SDL_PIXELFORMAT_RGB332,
    xrgb4444 = raw.SDL_PIXELFORMAT_XRGB4444,
    xbgr4444 = raw.SDL_PIXELFORMAT_XBGR4444,
    xrgb1555 = raw.SDL_PIXELFORMAT_XRGB1555,
    xbgr1555 = raw.SDL_PIXELFORMAT_XBGR1555,
    argb4444 = raw.SDL_PIXELFORMAT_ARGB4444,
    rgba4444 = raw.SDL_PIXELFORMAT_RGBA4444,
    abgr4444 = raw.SDL_PIXELFORMAT_ABGR4444,
    bgra4444 = raw.SDL_PIXELFORMAT_BGRA4444,
    argb1555 = raw.SDL_PIXELFORMAT_ARGB1555,
    rgba5551 = raw.SDL_PIXELFORMAT_RGBA5551,
    abgr1555 = raw.SDL_PIXELFORMAT_ABGR1555,
    bgra5551 = raw.SDL_PIXELFORMAT_BGRA5551,
    rgb565 = raw.SDL_PIXELFORMAT_RGB565,
    bgr565 = raw.SDL_PIXELFORMAT_BGR565,
    rgb24 = raw.SDL_PIXELFORMAT_RGB24,
    bgr24 = raw.SDL_PIXELFORMAT_BGR24,
    xrgb8888 = raw.SDL_PIXELFORMAT_XRGB8888,
    rgbx8888 = raw.SDL_PIXELFORMAT_RGBX8888,
    xbgr8888 = raw.SDL_PIXELFORMAT_XBGR8888,
    bgrx8888 = raw.SDL_PIXELFORMAT_BGRX8888,
    argb8888 = raw.SDL_PIXELFORMAT_ARGB8888,
    rgba8888 = raw.SDL_PIXELFORMAT_RGBA8888,
    abgr8888 = raw.SDL_PIXELFORMAT_ABGR8888,
    bgra8888 = raw.SDL_PIXELFORMAT_BGRA8888,
    xrgb2101010 = raw.SDL_PIXELFORMAT_XRGB2101010,
    xbgr2101010 = raw.SDL_PIXELFORMAT_XBGR2101010,
    argb2101010 = raw.SDL_PIXELFORMAT_ARGB2101010,
    abgr2101010 = raw.SDL_PIXELFORMAT_ABGR2101010,
    rgb48 = raw.SDL_PIXELFORMAT_RGB48,
    bgr48 = raw.SDL_PIXELFORMAT_BGR48,
    rgba64 = raw.SDL_PIXELFORMAT_RGBA64,
    argb64 = raw.SDL_PIXELFORMAT_ARGB64,
    bgra64 = raw.SDL_PIXELFORMAT_BGRA64,
    abgr64 = raw.SDL_PIXELFORMAT_ABGR64,
    rgb48_float = raw.SDL_PIXELFORMAT_RGB48_FLOAT,
    bgr48_float = raw.SDL_PIXELFORMAT_BGR48_FLOAT,
    rgba64_float = raw.SDL_PIXELFORMAT_RGBA64_FLOAT,
    argb64_float = raw.SDL_PIXELFORMAT_ARGB64_FLOAT,
    bgra64_float = raw.SDL_PIXELFORMAT_BGRA64_FLOAT,
    abgr64_float = raw.SDL_PIXELFORMAT_ABGR64_FLOAT,
    rgb96_float = raw.SDL_PIXELFORMAT_RGB96_FLOAT,
    bgr96_float = raw.SDL_PIXELFORMAT_BGR96_FLOAT,
    rgba128_float = raw.SDL_PIXELFORMAT_RGBA128_FLOAT,
    argb128_float = raw.SDL_PIXELFORMAT_ARGB128_FLOAT,
    bgra128_float = raw.SDL_PIXELFORMAT_BGRA128_FLOAT,
    abgr128_float = raw.SDL_PIXELFORMAT_ABGR128_FLOAT,
    yv12 = raw.SDL_PIXELFORMAT_YV12,
    iyuv = raw.SDL_PIXELFORMAT_IYUV,
    yuy2 = raw.SDL_PIXELFORMAT_YUY2,
    uyvy = raw.SDL_PIXELFORMAT_UYVY,
    yvyu = raw.SDL_PIXELFORMAT_YVYU,
    nv12 = raw.SDL_PIXELFORMAT_NV12,
    nv21 = raw.SDL_PIXELFORMAT_NV21,
    p010 = raw.SDL_PIXELFORMAT_P010,
    external_oes = raw.SDL_PIXELFORMAT_EXTERNAL_OES,
    mjpg = raw.SDL_PIXELFORMAT_MJPG,
    _,

    /// The endian-independent aliases: on every platform these name the
    /// format whose bytes are in the written order.
    pub const rgba32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_RGBA32));
    pub const argb32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_ARGB32));
    pub const bgra32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_BGRA32));
    pub const abgr32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_ABGR32));
    pub const rgbx32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_RGBX32));
    pub const xrgb32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_XRGB32));
    pub const bgrx32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_BGRX32));
    pub const xbgr32: PixelFormat = @fromBackingInt(@intCast(raw.SDL_PIXELFORMAT_XBGR32));

    /// SDL's own name for the format, such as "SDL_PIXELFORMAT_RGBA8888".
    /// Owned by SDL.
    pub fn name(self: PixelFormat) []const u8 {
        return std.mem.span(raw.SDL_GetPixelFormatName(@backingInt(self)));
    }

    /// Bit layout and masks. Null for a format SDL does not know how to
    /// describe, which includes every planar YUV format.
    pub fn details(self: PixelFormat) ?*const Details {
        return @ptrCast(raw.SDL_GetPixelFormatDetails(@backingInt(self)));
    }

    pub fn bytesPerPixel(self: PixelFormat) u8 {
        const d = self.details() orelse return 0;
        return d.bytes_per_pixel;
    }

    /// The bit layout SDL uses to pack and unpack pixels of one format.
    /// Layout-compatible with `SDL_PixelFormatDetails`.
    pub const Details = extern struct {
        format: PixelFormat,
        bits_per_pixel: u8,
        bytes_per_pixel: u8,
        padding: [2]u8,
        r_mask: u32,
        g_mask: u32,
        b_mask: u32,
        a_mask: u32,
        r_bits: u8,
        g_bits: u8,
        b_bits: u8,
        a_bits: u8,
        r_shift: u8,
        g_shift: u8,
        b_shift: u8,
        a_shift: u8,

        /// Packs a colour into a pixel of this format. Alpha is dropped for a
        /// format that has no alpha channel.
        pub fn map(self: *const Details, color: Color, palette: ?*const Palette) u32 {
            return raw.SDL_MapRGBA(
                @ptrCast(self),
                @ptrCast(palette),
                color.r,
                color.g,
                color.b,
                color.a,
            );
        }

        /// Unpacks a pixel. A format with no alpha channel reports 255.
        pub fn unmap(self: *const Details, pixel: u32, palette: ?*const Palette) Color {
            var color: Color = .{};
            raw.SDL_GetRGBA(
                pixel,
                @ptrCast(self),
                @ptrCast(palette),
                &color.r,
                &color.g,
                &color.b,
                &color.a,
            );
            return color;
        }
    };
};

/// A colour table for the indexed formats. Reference-counted by SDL: a
/// surface that is given a palette keeps it alive past `deinit`.
pub const Palette = extern struct {
    ncolors: c_int,
    colors_ptr: [*]Color,
    version: u32,
    refcount: c_int,

    pub fn init(color_count: usize) Error!*Palette {
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Palette, raw.SDL_CreatePalette(@intCast(color_count)))));
    }

    pub fn deinit(self: *Palette) void {
        raw.SDL_DestroyPalette(@ptrCast(self));
    }

    pub fn colors(self: *Palette) []Color {
        return self.colors_ptr[0..@intCast(self.ncolors)];
    }

    /// Replaces `new_colors.len` entries starting at `first`.
    pub fn setColors(self: *Palette, first: usize, new_colors: []const Color) Error!void {
        try check(raw.SDL_SetPaletteColors(
            @ptrCast(self),
            @ptrCast(new_colors.ptr),
            @intCast(first),
            @intCast(new_colors.len),
        ));
    }
};

comptime {
    std.debug.assert(@sizeOf(Color) == @sizeOf(raw.SDL_Color));
    std.debug.assert(@sizeOf(FColor) == @sizeOf(raw.SDL_FColor));
    std.debug.assert(@sizeOf(Palette) == @sizeOf(raw.SDL_Palette));
    std.debug.assert(@sizeOf(PixelFormat.Details) == @sizeOf(raw.SDL_PixelFormatDetails));
}
