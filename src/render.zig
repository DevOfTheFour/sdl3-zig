//! SDL's 2D renderer: hardware-accelerated sprites, rectangles and geometry,
//! on whichever backend the platform gives you.
//!
//! `Renderer` and `Texture` are handles, one pointer wide. Both are destroyed
//! explicitly; destroying a renderer also destroys the textures made from it,
//! so the usual order is `defer texture.deinit()` before
//! `defer renderer.deinit()`.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const pixels_mod = @import("pixels.zig");
const rect_mod = @import("rect.zig");
const surface_mod = @import("surface.zig");
const video_mod = @import("video.zig");
const properties_mod = @import("properties.zig");

const Error = errors.Error;
const check = errors.check;
const Color = pixels_mod.Color;
const FColor = pixels_mod.FColor;
const BlendMode = pixels_mod.BlendMode;
const ScaleMode = pixels_mod.ScaleMode;
const FlipMode = pixels_mod.FlipMode;
const PixelFormat = pixels_mod.PixelFormat;
const Rect = rect_mod.Rect;
const FRect = rect_mod.FRect;
const FPoint = rect_mod.FPoint;
const Size = rect_mod.Size;
const Surface = surface_mod.Surface;
const Window = video_mod.Window;
const Properties = properties_mod.Properties;

/// One vertex for `Renderer.geometry`. Layout-compatible with `SDL_Vertex`.
pub const Vertex = extern struct {
    position: FPoint = .{},
    color: FColor = .{},
    /// Normalised 0..1, ignored when no texture is bound.
    tex_coord: FPoint = .{},
};

pub const TextureAccess = enum(c_uint) {
    /// Uploaded rarely, with `update`.
    static = raw.SDL_TEXTUREACCESS_STATIC,
    /// Written every frame, through `lock`.
    streaming = raw.SDL_TEXTUREACCESS_STREAMING,
    /// Can be drawn into with `setTarget`.
    target = raw.SDL_TEXTUREACCESS_TARGET,
    _,
};

/// How a logical resolution is fitted to a differently-shaped window.
pub const LogicalPresentation = enum(c_uint) {
    disabled = raw.SDL_LOGICAL_PRESENTATION_DISABLED,
    /// Fill the window, distorting the aspect ratio.
    stretch = raw.SDL_LOGICAL_PRESENTATION_STRETCH,
    /// Keep the aspect ratio, with bars on two sides.
    letterbox = raw.SDL_LOGICAL_PRESENTATION_LETTERBOX,
    /// Keep the aspect ratio, cropping instead of adding bars.
    overscan = raw.SDL_LOGICAL_PRESENTATION_OVERSCAN,
    /// Scale by whole numbers only: the pixel-art choice.
    integer_scale = raw.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE,
    _,
};

pub const TextureAddressMode = enum(c_int) {
    invalid = raw.SDL_TEXTURE_ADDRESS_INVALID,
    auto = raw.SDL_TEXTURE_ADDRESS_AUTO,
    clamp = raw.SDL_TEXTURE_ADDRESS_CLAMP,
    wrap = raw.SDL_TEXTURE_ADDRESS_WRAP,
    _,
};

/// Values `Renderer.setVSync` takes beyond a plain frame count.
pub const vsync_disabled: i32 = 0;
pub const vsync_adaptive: i32 = -1;

pub fn driverCount() usize {
    const count = raw.SDL_GetNumRenderDrivers();
    return if (count < 0) 0 else @intCast(count);
}

/// "metal", "opengl", "vulkan", "software", and so on.
pub fn driverName(index: usize) ?[]const u8 {
    const name = raw.SDL_GetRenderDriver(@intCast(index));
    if (name == null) return null;
    return std.mem.span(name);
}

/// A window and a renderer for it, created together. The common opening move.
pub const WindowAndRenderer = struct {
    window: Window,
    renderer: Renderer,
};

pub fn createWindowAndRenderer(
    title: [:0]const u8,
    width: i32,
    height: i32,
    flags: video_mod.WindowFlags,
) Error!WindowAndRenderer {
    var window: ?*raw.SDL_Window = null;
    var renderer: ?*raw.SDL_Renderer = null;
    try check(raw.SDL_CreateWindowAndRenderer(
        title.ptr,
        width,
        height,
        @bitCast(flags),
        &window,
        &renderer,
    ));
    return .{
        .window = .{ .handle = window.? },
        .renderer = .{ .handle = renderer.? },
    };
}

pub const Renderer = struct {
    handle: *raw.SDL_Renderer,

    /// `driver` picks a specific backend by name; null lets SDL choose, which
    /// is almost always what you want.
    pub fn init(target_window: Window, driver: ?[:0]const u8) Error!Renderer {
        const handle = raw.SDL_CreateRenderer(
            target_window.handle,
            if (driver) |d| d.ptr else null,
        );
        return .{ .handle = try errors.checkPtr(handle) };
    }

    /// A renderer that draws into a surface on the CPU. No window needed,
    /// which is what makes it the one renderer that works headless.
    pub fn initSoftware(target: *Surface) Error!Renderer {
        const handle = raw.SDL_CreateSoftwareRenderer(@ptrCast(target));
        return .{ .handle = try errors.checkPtr(handle) };
    }

    /// The renderer already attached to a window, if it has one.
    pub fn fromWindow(source: Window) ?Renderer {
        const handle = raw.SDL_GetRenderer(source.handle) orelse return null;
        return .{ .handle = handle };
    }

    pub fn deinit(self: Renderer) void {
        raw.SDL_DestroyRenderer(self.handle);
    }

    /// Owned by SDL.
    pub fn name(self: Renderer) []const u8 {
        const text = raw.SDL_GetRendererName(self.handle);
        if (text == null) return "";
        return std.mem.span(text);
    }

    pub fn properties(self: Renderer) Properties {
        return .{ .id = raw.SDL_GetRendererProperties(self.handle) };
    }

    /// Null for a software renderer.
    pub fn window(self: Renderer) ?Window {
        const handle = raw.SDL_GetRenderWindow(self.handle) orelse return null;
        return .{ .handle = handle };
    }

    /// The size of what is being drawn into, in pixels.
    pub fn outputSize(self: Renderer) Error!Size {
        var w: c_int = 0;
        var h: c_int = 0;
        try check(raw.SDL_GetRenderOutputSize(self.handle, &w, &h));
        return .{ .width = w, .height = h };
    }

    // -- frame ----------------------------------------------------------

    /// Fills the target with the current draw colour, ignoring the clip rect.
    pub fn clear(self: Renderer) Error!void {
        try check(raw.SDL_RenderClear(self.handle));
    }

    /// Puts the frame on screen. Everything drawn since the last `present` is
    /// batched until here, so a frame costs one flush, not one per call.
    pub fn present(self: Renderer) Error!void {
        try check(raw.SDL_RenderPresent(self.handle));
    }

    /// 1 waits for one refresh, `vsync_disabled` never waits,
    /// `vsync_adaptive` waits unless the frame was late.
    pub fn setVSync(self: Renderer, vsync: i32) Error!void {
        try check(raw.SDL_SetRenderVSync(self.handle, vsync));
    }

    // -- state ----------------------------------------------------------

    pub fn setDrawColor(self: Renderer, color: Color) Error!void {
        try check(raw.SDL_SetRenderDrawColor(self.handle, color.r, color.g, color.b, color.a));
    }

    pub fn drawColor(self: Renderer) Error!Color {
        var color: Color = .{};
        try check(raw.SDL_GetRenderDrawColor(self.handle, &color.r, &color.g, &color.b, &color.a));
        return color;
    }

    pub fn setDrawColorFloat(self: Renderer, color: FColor) Error!void {
        try check(raw.SDL_SetRenderDrawColorFloat(self.handle, color.r, color.g, color.b, color.a));
    }

    pub fn setDrawBlendMode(self: Renderer, mode: BlendMode) Error!void {
        try check(raw.SDL_SetRenderDrawBlendMode(self.handle, @backingInt(mode)));
    }

    /// Draw in a fixed resolution and let SDL fit it to the window. The whole
    /// of a pixel-art game's scaling problem, solved in one call.
    pub fn setLogicalPresentation(
        self: Renderer,
        width: i32,
        height: i32,
        mode: LogicalPresentation,
    ) Error!void {
        try check(raw.SDL_SetRenderLogicalPresentation(
            self.handle,
            width,
            height,
            @backingInt(mode),
        ));
    }

    /// Pass null to draw to the whole target again.
    pub fn setViewport(self: Renderer, area: ?Rect) Error!void {
        const ptr: [*c]const raw.SDL_Rect = if (area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_SetRenderViewport(self.handle, ptr));
    }

    pub fn setClipRect(self: Renderer, area: ?Rect) Error!void {
        const ptr: [*c]const raw.SDL_Rect = if (area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_SetRenderClipRect(self.handle, ptr));
    }

    pub fn setScale(self: Renderer, x: f32, y: f32) Error!void {
        try check(raw.SDL_SetRenderScale(self.handle, x, y));
    }

    /// Draws into `texture` instead of the window. The texture must have been
    /// created with `.target` access. Pass null to go back to the window.
    pub fn setTarget(self: Renderer, target: ?Texture) Error!void {
        try check(raw.SDL_SetRenderTarget(
            self.handle,
            if (target) |t| t.handle else null,
        ));
    }

    // -- drawing --------------------------------------------------------

    pub fn point(self: Renderer, x: f32, y: f32) Error!void {
        try check(raw.SDL_RenderPoint(self.handle, x, y));
    }

    pub fn points(self: Renderer, list: []const FPoint) Error!void {
        try check(raw.SDL_RenderPoints(self.handle, @ptrCast(list.ptr), @intCast(list.len)));
    }

    pub fn line(self: Renderer, x1: f32, y1: f32, x2: f32, y2: f32) Error!void {
        try check(raw.SDL_RenderLine(self.handle, x1, y1, x2, y2));
    }

    /// A connected polyline through every point.
    pub fn lines(self: Renderer, list: []const FPoint) Error!void {
        try check(raw.SDL_RenderLines(self.handle, @ptrCast(list.ptr), @intCast(list.len)));
    }

    /// The outline. Null draws the whole target's outline.
    pub fn rect(self: Renderer, area: ?FRect) Error!void {
        const ptr: [*c]const raw.SDL_FRect = if (area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_RenderRect(self.handle, ptr));
    }

    pub fn rects(self: Renderer, list: []const FRect) Error!void {
        try check(raw.SDL_RenderRects(self.handle, @ptrCast(list.ptr), @intCast(list.len)));
    }

    pub fn fillRect(self: Renderer, area: ?FRect) Error!void {
        const ptr: [*c]const raw.SDL_FRect = if (area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_RenderFillRect(self.handle, ptr));
    }

    pub fn fillRects(self: Renderer, list: []const FRect) Error!void {
        try check(raw.SDL_RenderFillRects(self.handle, @ptrCast(list.ptr), @intCast(list.len)));
    }

    /// Draws `src` of `texture` into `dst`. Null means the whole of either.
    pub fn texture(self: Renderer, tex: Texture, src: ?FRect, dst: ?FRect) Error!void {
        const src_ptr: [*c]const raw.SDL_FRect = if (src) |r| @ptrCast(&r) else null;
        const dst_ptr: [*c]const raw.SDL_FRect = if (dst) |r| @ptrCast(&r) else null;
        try check(raw.SDL_RenderTexture(self.handle, tex.handle, src_ptr, dst_ptr));
    }

    /// `angle` is in degrees, clockwise. `center` is relative to `dst`, and
    /// null means the centre of `dst`.
    pub fn textureRotated(
        self: Renderer,
        tex: Texture,
        src: ?FRect,
        dst: ?FRect,
        angle: f64,
        center: ?FPoint,
        flip: FlipMode,
    ) Error!void {
        const src_ptr: [*c]const raw.SDL_FRect = if (src) |r| @ptrCast(&r) else null;
        const dst_ptr: [*c]const raw.SDL_FRect = if (dst) |r| @ptrCast(&r) else null;
        const center_ptr: [*c]const raw.SDL_FPoint = if (center) |p| @ptrCast(&p) else null;
        try check(raw.SDL_RenderTextureRotated(
            self.handle,
            tex.handle,
            src_ptr,
            dst_ptr,
            angle,
            center_ptr,
            @backingInt(flip),
        ));
    }

    /// Repeats `src` across `dst` instead of stretching it.
    pub fn textureTiled(
        self: Renderer,
        tex: Texture,
        src: ?FRect,
        scale: f32,
        dst: ?FRect,
    ) Error!void {
        const src_ptr: [*c]const raw.SDL_FRect = if (src) |r| @ptrCast(&r) else null;
        const dst_ptr: [*c]const raw.SDL_FRect = if (dst) |r| @ptrCast(&r) else null;
        try check(raw.SDL_RenderTextureTiled(self.handle, tex.handle, src_ptr, scale, dst_ptr));
    }

    /// Triangles, three vertices at a time. `indices` may be empty, in which
    /// case the vertices are taken in order. `tex` null draws flat colour.
    pub fn geometry(
        self: Renderer,
        tex: ?Texture,
        vertices: []const Vertex,
        indices: []const c_int,
    ) Error!void {
        try check(raw.SDL_RenderGeometry(
            self.handle,
            if (tex) |t| t.handle else null,
            @ptrCast(vertices.ptr),
            @intCast(vertices.len),
            if (indices.len == 0) null else indices.ptr,
            @intCast(indices.len),
        ));
    }

    /// SDL's built-in 8x8 debug font. No font file, no dependency -- for
    /// frame counters and overlays, not for UI text.
    pub fn debugText(self: Renderer, x: f32, y: f32, text: [:0]const u8) Error!void {
        try check(raw.SDL_RenderDebugText(self.handle, x, y, text.ptr));
    }

    // -- readback -------------------------------------------------------

    /// A new surface holding what has been drawn so far. Slow: it stalls the
    /// pipeline. The caller owns the surface.
    pub fn readPixels(self: Renderer, area: ?Rect) Error!*Surface {
        const ptr: [*c]const raw.SDL_Rect = if (area) |r| @ptrCast(&r) else null;
        const handle = raw.SDL_RenderReadPixels(self.handle, ptr);
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, handle)));
    }

    /// Window coordinates to render coordinates, undoing the logical
    /// presentation and scale. Mouse events need this before they are
    /// compared against anything drawn.
    pub fn coordinatesFromWindow(self: Renderer, window_x: f32, window_y: f32) Error!FPoint {
        var out: FPoint = .{};
        try check(raw.SDL_RenderCoordinatesFromWindow(self.handle, window_x, window_y, &out.x, &out.y));
        return out;
    }
};

pub const Texture = struct {
    handle: *raw.SDL_Texture,

    pub fn init(
        renderer: Renderer,
        format: PixelFormat,
        access: TextureAccess,
        width: i32,
        height: i32,
    ) Error!Texture {
        const handle = raw.SDL_CreateTexture(
            renderer.handle,
            @backingInt(format),
            @backingInt(access),
            width,
            height,
        );
        return .{ .handle = try errors.checkPtr(@as(?*raw.SDL_Texture, handle)) };
    }

    /// Uploads a surface. The surface can be freed straight after.
    pub fn initFromSurface(renderer: Renderer, source: *Surface) Error!Texture {
        const handle = raw.SDL_CreateTextureFromSurface(renderer.handle, @ptrCast(source));
        return .{ .handle = try errors.checkPtr(@as(?*raw.SDL_Texture, handle)) };
    }

    pub fn deinit(self: Texture) void {
        raw.SDL_DestroyTexture(self.handle);
    }

    /// Float, because a texture's size participates in float draw maths.
    pub fn size(self: Texture) Error!rect_mod.FSize {
        var w: f32 = 0;
        var h: f32 = 0;
        try check(raw.SDL_GetTextureSize(self.handle, &w, &h));
        return .{ .width = w, .height = h };
    }

    pub fn properties(self: Texture) Properties {
        return .{ .id = raw.SDL_GetTextureProperties(self.handle) };
    }

    /// Replaces `area` (or all of it) with `data`. `pitch` is the byte stride
    /// of a row in `data`, which is not always the row's width in pixels.
    pub fn update(self: Texture, area: ?Rect, data: []const u8, pitch: usize) Error!void {
        const ptr: [*c]const raw.SDL_Rect = if (area) |r| @ptrCast(&r) else null;
        try check(raw.SDL_UpdateTexture(self.handle, ptr, data.ptr, @intCast(pitch)));
    }

    /// Write access to a `.streaming` texture's pixels. What comes back is
    /// write-only staging memory: reading it is legal but slow, and its
    /// contents are undefined. Always pair with `unlock`.
    pub fn lock(self: Texture, area: ?Rect) Error!Locked {
        const ptr: [*c]const raw.SDL_Rect = if (area) |r| @ptrCast(&r) else null;
        var data: ?*anyopaque = null;
        var pitch: c_int = 0;
        try check(raw.SDL_LockTexture(self.handle, ptr, &data, &pitch));

        const height: usize = if (area) |r|
            @intCast(r.h)
        else
            @intFromFloat((try self.size()).height);

        const base: [*]u8 = @ptrCast(data.?);
        return .{
            .pixels = base[0 .. @as(usize, @intCast(pitch)) * height],
            .pitch = @intCast(pitch),
        };
    }

    pub const Locked = struct {
        pixels: []u8,
        pitch: usize,
    };

    /// Uploads what was written and invalidates the slice from `lock`.
    pub fn unlock(self: Texture) void {
        raw.SDL_UnlockTexture(self.handle);
    }

    pub fn setBlendMode(self: Texture, mode: BlendMode) Error!void {
        try check(raw.SDL_SetTextureBlendMode(self.handle, @backingInt(mode)));
    }

    pub fn setScaleMode(self: Texture, mode: ScaleMode) Error!void {
        try check(raw.SDL_SetTextureScaleMode(self.handle, @backingInt(mode)));
    }

    /// Multiplies the texture's colours as it is drawn. Tinting, without a
    /// second copy of the texture.
    pub fn setColorMod(self: Texture, r: u8, g: u8, b: u8) Error!void {
        try check(raw.SDL_SetTextureColorMod(self.handle, r, g, b));
    }

    pub fn setAlphaMod(self: Texture, alpha: u8) Error!void {
        try check(raw.SDL_SetTextureAlphaMod(self.handle, alpha));
    }
};

comptime {
    std.debug.assert(@sizeOf(Vertex) == @sizeOf(raw.SDL_Vertex));
}
