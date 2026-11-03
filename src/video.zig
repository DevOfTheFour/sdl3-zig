//! Displays and windows.
//!
//! `Window` is a thin handle: SDL owns the window, and the struct is one
//! pointer wide, so it is copied freely and compared by handle. Events do not
//! carry it -- they carry a `WindowId` -- so `Window.fromId` is how an event
//! finds the window it belongs to.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const pixels_mod = @import("pixels.zig");
const rect_mod = @import("rect.zig");
const surface_mod = @import("surface.zig");
const properties_mod = @import("properties.zig");

const Error = errors.Error;
const check = errors.check;
const PixelFormat = pixels_mod.PixelFormat;
const Rect = rect_mod.Rect;
const Point = rect_mod.Point;
const Size = rect_mod.Size;
const Surface = surface_mod.Surface;
const Properties = properties_mod.Properties;

pub const DisplayId = u32;
pub const WindowId = u32;

// ---------------------------------------------------------------------
// Video drivers
// ---------------------------------------------------------------------

/// The driver SDL actually chose: "cocoa", "wayland", "x11", "windows",
/// "dummy". Null before `sdl.init`.
pub fn currentDriver() ?[]const u8 {
    const name = raw.SDL_GetCurrentVideoDriver();
    if (name == null) return null;
    return std.mem.span(name);
}

pub fn driverCount() usize {
    const count = raw.SDL_GetNumVideoDrivers();
    return if (count < 0) 0 else @intCast(count);
}

pub fn driverName(index: usize) ?[]const u8 {
    const name = raw.SDL_GetVideoDriver(@intCast(index));
    if (name == null) return null;
    return std.mem.span(name);
}

pub const SystemTheme = enum(c_uint) {
    unknown = raw.SDL_SYSTEM_THEME_UNKNOWN,
    light = raw.SDL_SYSTEM_THEME_LIGHT,
    dark = raw.SDL_SYSTEM_THEME_DARK,
    _,
};

pub fn systemTheme() SystemTheme {
    return @fromBackingInt(@intCast(raw.SDL_GetSystemTheme()));
}

pub fn screenSaverEnabled() bool {
    return raw.SDL_ScreenSaverEnabled();
}

/// SDL disables the screen saver on `init` for video, on the assumption that a
/// game is running. Re-enable it for an application that sits idle.
pub fn setScreenSaverEnabled(enabled: bool) Error!void {
    try check(if (enabled) raw.SDL_EnableScreenSaver() else raw.SDL_DisableScreenSaver());
}

// ---------------------------------------------------------------------
// Displays
// ---------------------------------------------------------------------

pub const DisplayOrientation = enum(c_uint) {
    unknown = raw.SDL_ORIENTATION_UNKNOWN,
    landscape = raw.SDL_ORIENTATION_LANDSCAPE,
    landscape_flipped = raw.SDL_ORIENTATION_LANDSCAPE_FLIPPED,
    portrait = raw.SDL_ORIENTATION_PORTRAIT,
    portrait_flipped = raw.SDL_ORIENTATION_PORTRAIT_FLIPPED,
    _,
};

/// One entry from a display's mode list. Layout-compatible with
/// `SDL_DisplayMode`, so SDL's own pointers are read in place.
pub const DisplayMode = extern struct {
    display_id: DisplayId = 0,
    format: PixelFormat = .unknown,
    w: c_int = 0,
    h: c_int = 0,
    /// Pixels per screen coordinate: 2.0 on a Retina display.
    pixel_density: f32 = 0,
    refresh_rate: f32 = 0,
    refresh_rate_numerator: c_int = 0,
    refresh_rate_denominator: c_int = 0,
    internal: ?*anyopaque = null,

    pub fn size(self: DisplayMode) Size {
        return .{ .width = self.w, .height = self.h };
    }
};

/// A monitor. The id is SDL's; it stays valid until the display is
/// disconnected, and there is nothing to free.
pub const Display = struct {
    id: DisplayId,

    /// Every connected display, in SDL's own order. The slice is owned by SDL
    /// and freed by `freeDisplays`.
    pub fn all() Error![]const DisplayId {
        var count: c_int = 0;
        const list = try errors.checkPtr(@as(?[*]DisplayId, raw.SDL_GetDisplays(&count)));
        return list[0..@intCast(count)];
    }

    /// Frees the slice `all` returned.
    pub fn freeDisplays(list: []const DisplayId) void {
        raw.SDL_free(@ptrCast(@constCast(list.ptr)));
    }

    pub fn primary() Error!Display {
        const id = raw.SDL_GetPrimaryDisplay();
        if (id == 0) return Error.SdlError;
        return .{ .id = id };
    }

    /// The display a point falls on, or null when it falls on none.
    pub fn forPoint(point: Point) ?Display {
        const id = raw.SDL_GetDisplayForPoint(@ptrCast(&point));
        return if (id == 0) null else .{ .id = id };
    }

    /// Owned by SDL.
    pub fn name(self: Display) []const u8 {
        const text = raw.SDL_GetDisplayName(self.id);
        if (text == null) return "";
        return std.mem.span(text);
    }

    /// Where this display sits in the desktop's coordinate space.
    pub fn bounds(self: Display) Error!Rect {
        var result: Rect = .{};
        try check(raw.SDL_GetDisplayBounds(self.id, @ptrCast(&result)));
        return result;
    }

    /// `bounds` minus the taskbar, dock and menu bar.
    pub fn usableBounds(self: Display) Error!Rect {
        var result: Rect = .{};
        try check(raw.SDL_GetDisplayUsableBounds(self.id, @ptrCast(&result)));
        return result;
    }

    /// The scale the desktop is drawn at: 2.0 on a Retina display. This is
    /// the number to size UI against, not the physical DPI.
    pub fn contentScale(self: Display) f32 {
        return raw.SDL_GetDisplayContentScale(self.id);
    }

    pub fn orientation(self: Display) DisplayOrientation {
        return @fromBackingInt(@intCast(raw.SDL_GetCurrentDisplayOrientation(self.id)));
    }

    /// The mode the desktop is using. Borrowed from SDL.
    pub fn desktopMode(self: Display) Error!*const DisplayMode {
        const mode = raw.SDL_GetDesktopDisplayMode(self.id);
        return @ptrCast(try errors.checkPtr(@as(?*const raw.SDL_DisplayMode, mode)));
    }

    /// The mode currently in effect, which differs from `desktopMode` while a
    /// fullscreen window has changed it.
    pub fn currentMode(self: Display) Error!*const DisplayMode {
        const mode = raw.SDL_GetCurrentDisplayMode(self.id);
        return @ptrCast(try errors.checkPtr(@as(?*const raw.SDL_DisplayMode, mode)));
    }

    /// Iterates the fullscreen modes this display advertises, largest first.
    /// Call `deinit` on the iterator: the array is SDL's to free.
    pub fn fullscreenModes(self: Display) Error!ModeIterator {
        // SDL 3.4.18 may invoke memcpy with a null source
        // when the display has zero fullscreen modes.
        //
        // The dummy video driver does not expose fullscreen
        // modes, so return an empty iterator without calling
        // SDL_GetFullscreenDisplayModes().
        if (currentDriver()) |driver| {
            if (std.mem.eql(u8, driver, "dummy")) {
                // Preserve invalid-display error handling.
                _ = try self.desktopMode();

                return .{
                    .modes = &.{},
                    .owns_memory = false,
                };
            }
        }

        var count: c_int = 0;

        const list = try errors.checkPtr(@as(
            ?[*]const *const DisplayMode,
            @ptrCast(raw.SDL_GetFullscreenDisplayModes(
                self.id,
                &count,
            )),
        ));

        return .{
            .modes = list[0..@intCast(count)],
        };
    }

    pub const ModeIterator = struct {
        modes: []const *const DisplayMode,
        index: usize = 0,

        // True only when the array was allocated by SDL.
        owns_memory: bool = true,

        pub fn next(self: *ModeIterator) ?*const DisplayMode {
            if (self.index == self.modes.len)
                return null;

            defer self.index += 1;
            return self.modes[self.index];
        }

        pub fn count(self: ModeIterator) usize {
            return self.modes.len;
        }

        pub fn deinit(self: ModeIterator) void {
            if (self.owns_memory) {
                raw.SDL_free(
                    @ptrCast(@constCast(self.modes.ptr)),
                );
            }
        }
    };

    /// The advertised mode closest to what was asked for.
    pub fn closestMode(
        self: Display,
        width: i32,
        height: i32,
        refresh_rate: f32,
        include_high_density: bool,
    ) Error!DisplayMode {
        var mode: DisplayMode = .{};
        try check(raw.SDL_GetClosestFullscreenDisplayMode(
            self.id,
            width,
            height,
            refresh_rate,
            include_high_density,
            @ptrCast(&mode),
        ));
        return mode;
    }

    pub fn properties(self: Display) Properties {
        return .{ .id = raw.SDL_GetDisplayProperties(self.id) };
    }
};

// ---------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------

/// Window creation and state flags, as named bits rather than an or-ed
/// integer. The same type reports state back from `Window.flags`.
pub const WindowFlags = packed struct(u64) {
    fullscreen: bool = false,
    /// The window will be used with OpenGL. Required before any GL call.
    opengl: bool = false,
    /// Read-only: another window is covering this one entirely.
    occluded: bool = false,
    /// Created hidden. Call `show` when the first frame is ready, and the
    /// window never appears empty.
    hidden: bool = false,
    borderless: bool = false,
    resizable: bool = false,
    minimized: bool = false,
    maximized: bool = false,
    mouse_grabbed: bool = false,
    /// Read-only.
    input_focus: bool = false,
    /// Read-only.
    mouse_focus: bool = false,
    /// Read-only: the window was created from a native handle.
    external: bool = false,
    modal: bool = false,
    /// Ask for a backing store at the display's real pixel density. Without
    /// it a Retina window renders at half resolution and is upscaled.
    high_pixel_density: bool = false,
    mouse_capture: bool = false,
    mouse_relative_mode: bool = false,
    always_on_top: bool = false,
    utility: bool = false,
    tooltip: bool = false,
    popup_menu: bool = false,
    keyboard_grabbed: bool = false,
    fill_document: bool = false,
    _reserved0: u6 = 0,
    /// The window will be used with Vulkan.
    vulkan: bool = false,
    /// The window will be used with Metal.
    metal: bool = false,
    transparent: bool = false,
    not_focusable: bool = false,
    _reserved1: u32 = 0,
};

pub const FlashOperation = enum(c_uint) {
    cancel = raw.SDL_FLASH_CANCEL,
    briefly = raw.SDL_FLASH_BRIEFLY,
    until_focused = raw.SDL_FLASH_UNTIL_FOCUSED,
    _,
};

/// A window. One pointer wide, so pass it by value.
pub const Window = struct {
    handle: *raw.SDL_Window,

    /// `title` is `[:0]const u8` so string literals pass with no conversion.
    /// The size is in screen coordinates, not pixels -- see `sizeInPixels`.
    pub fn init(window_title: [:0]const u8, width: i32, height: i32, window_flags: WindowFlags) Error!Window {
        const handle = raw.SDL_CreateWindow(window_title.ptr, width, height, @bitCast(window_flags));
        return .{ .handle = try errors.checkPtr(handle) };
    }

    pub fn deinit(self: Window) void {
        raw.SDL_DestroyWindow(self.handle);
    }

    /// The window an event refers to, or null when it has been destroyed
    /// since the event was queued.
    pub fn fromId(window_id: WindowId) ?Window {
        const handle = raw.SDL_GetWindowFromID(window_id) orelse return null;
        return .{ .handle = handle };
    }

    pub fn id(self: Window) WindowId {
        return raw.SDL_GetWindowID(self.handle);
    }

    pub fn flags(self: Window) WindowFlags {
        return @bitCast(raw.SDL_GetWindowFlags(self.handle));
    }

    pub fn properties(self: Window) Properties {
        return .{ .id = raw.SDL_GetWindowProperties(self.handle) };
    }

    pub fn display(self: Window) Error!Display {
        const display_id = raw.SDL_GetDisplayForWindow(self.handle);
        if (display_id == 0) return Error.SdlError;
        return .{ .id = display_id };
    }

    // -- lifecycle ------------------------------------------------------

    pub fn show(self: Window) Error!void {
        try check(raw.SDL_ShowWindow(self.handle));
    }

    pub fn hide(self: Window) Error!void {
        try check(raw.SDL_HideWindow(self.handle));
    }

    pub fn raiseWindow(self: Window) Error!void {
        try check(raw.SDL_RaiseWindow(self.handle));
    }

    pub fn minimize(self: Window) Error!void {
        try check(raw.SDL_MinimizeWindow(self.handle));
    }

    pub fn maximize(self: Window) Error!void {
        try check(raw.SDL_MaximizeWindow(self.handle));
    }

    pub fn restore(self: Window) Error!void {
        try check(raw.SDL_RestoreWindow(self.handle));
    }

    /// Window state changes are asynchronous on most platforms: the flags do
    /// not update until the window manager has acted. This blocks until they
    /// have, which is what a resize-then-measure sequence needs.
    pub fn sync(self: Window) Error!void {
        try check(raw.SDL_SyncWindow(self.handle));
    }

    /// Flashes the taskbar entry or bounces the dock icon.
    pub fn flash(self: Window, operation: FlashOperation) Error!void {
        try check(raw.SDL_FlashWindow(self.handle, @backingInt(operation)));
    }

    // -- geometry -------------------------------------------------------

    pub fn setTitle(self: Window, new_title: [:0]const u8) Error!void {
        try check(raw.SDL_SetWindowTitle(self.handle, new_title.ptr));
    }

    /// Owned by SDL.
    pub fn title(self: Window) []const u8 {
        const text = raw.SDL_GetWindowTitle(self.handle);
        if (text == null) return "";
        return std.mem.span(text);
    }

    /// Size in screen coordinates, which is *not* pixels on a high-DPI
    /// display. Use `sizeInPixels` for anything you render into.
    pub fn size(self: Window) Error!Size {
        var w: c_int = 0;
        var h: c_int = 0;
        try check(raw.SDL_GetWindowSize(self.handle, &w, &h));
        return .{ .width = w, .height = h };
    }

    pub fn setSize(self: Window, width: i32, height: i32) Error!void {
        try check(raw.SDL_SetWindowSize(self.handle, width, height));
    }

    /// Size in pixels. This is what a viewport or swapchain wants.
    pub fn sizeInPixels(self: Window) Error!Size {
        var w: c_int = 0;
        var h: c_int = 0;
        try check(raw.SDL_GetWindowSizeInPixels(self.handle, &w, &h));
        return .{ .width = w, .height = h };
    }

    /// Pixels per screen coordinate for this window: 2.0 on a Retina display,
    /// and 1.0 unless the window was created `high_pixel_density`.
    pub fn pixelDensity(self: Window) f32 {
        return raw.SDL_GetWindowPixelDensity(self.handle);
    }

    /// The scale the desktop asks content to be drawn at. Size UI against
    /// this; size framebuffers against `sizeInPixels`.
    pub fn displayScale(self: Window) f32 {
        return raw.SDL_GetWindowDisplayScale(self.handle);
    }

    pub fn position(self: Window) Error!Point {
        var x: c_int = 0;
        var y: c_int = 0;
        try check(raw.SDL_GetWindowPosition(self.handle, &x, &y));
        return .{ .x = x, .y = y };
    }

    pub fn setPosition(self: Window, x: i32, y: i32) Error!void {
        try check(raw.SDL_SetWindowPosition(self.handle, x, y));
    }

    pub fn setMinimumSize(self: Window, width: i32, height: i32) Error!void {
        try check(raw.SDL_SetWindowMinimumSize(self.handle, width, height));
    }

    pub fn setMaximumSize(self: Window, width: i32, height: i32) Error!void {
        try check(raw.SDL_SetWindowMaximumSize(self.handle, width, height));
    }

    /// The part of the window nothing overlaps: the notch and rounded corners
    /// on a phone, the whole client area on a desktop.
    pub fn safeArea(self: Window) Error!Rect {
        var result: Rect = .{};
        try check(raw.SDL_GetWindowSafeArea(self.handle, @ptrCast(&result)));
        return result;
    }

    // -- state ----------------------------------------------------------

    pub fn setResizable(self: Window, resizable: bool) Error!void {
        try check(raw.SDL_SetWindowResizable(self.handle, resizable));
    }

    pub fn setBordered(self: Window, bordered: bool) Error!void {
        try check(raw.SDL_SetWindowBordered(self.handle, bordered));
    }

    pub fn setAlwaysOnTop(self: Window, on_top: bool) Error!void {
        try check(raw.SDL_SetWindowAlwaysOnTop(self.handle, on_top));
    }

    /// SDL 3 has one fullscreen mode. It is borderless-desktop by default;
    /// call `setFullscreenMode` first for an exclusive video mode.
    pub fn setFullscreen(self: Window, fullscreen: bool) Error!void {
        try check(raw.SDL_SetWindowFullscreen(self.handle, fullscreen));
    }

    /// Pass null to go back to borderless-desktop fullscreen.
    pub fn setFullscreenMode(self: Window, mode: ?*const DisplayMode) Error!void {
        try check(raw.SDL_SetWindowFullscreenMode(self.handle, @ptrCast(mode)));
    }

    pub fn setOpacity(self: Window, value: f32) Error!void {
        try check(raw.SDL_SetWindowOpacity(self.handle, value));
    }

    pub fn opacity(self: Window) f32 {
        return raw.SDL_GetWindowOpacity(self.handle);
    }

    /// SDL copies the surface, so it can be freed straight after.
    pub fn setIcon(self: Window, icon: *Surface) Error!void {
        try check(raw.SDL_SetWindowIcon(self.handle, @ptrCast(icon)));
    }

    /// Confines the mouse to this window while it has focus.
    pub fn setMouseGrab(self: Window, grabbed: bool) Error!void {
        try check(raw.SDL_SetWindowMouseGrab(self.handle, grabbed));
    }

    pub fn setKeyboardGrab(self: Window, grabbed: bool) Error!void {
        try check(raw.SDL_SetWindowKeyboardGrab(self.handle, grabbed));
    }

    /// Relative mode hides the cursor and reports motion as deltas with no
    /// edges: what a first-person camera wants.
    pub fn setRelativeMouseMode(self: Window, enabled: bool) Error!void {
        try check(raw.SDL_SetWindowRelativeMouseMode(self.handle, enabled));
    }

    pub fn relativeMouseMode(self: Window) bool {
        return raw.SDL_GetWindowRelativeMouseMode(self.handle);
    }

    // -- the window surface ---------------------------------------------
    //
    // The software path: no renderer, no GPU, just pixels pushed to the
    // window. Fine for a tool; too slow for a game.

    /// Borrowed from SDL and invalidated by a resize -- fetch it again each
    /// time rather than caching it.
    pub fn surface(self: Window) Error!*Surface {
        const handle = raw.SDL_GetWindowSurface(self.handle);
        return @ptrCast(try errors.checkPtr(@as(?*raw.SDL_Surface, handle)));
    }

    pub fn updateSurface(self: Window) Error!void {
        try check(raw.SDL_UpdateWindowSurface(self.handle));
    }

    pub fn updateSurfaceRects(self: Window, rects: []const Rect) Error!void {
        try check(raw.SDL_UpdateWindowSurfaceRects(
            self.handle,
            @ptrCast(rects.ptr),
            @intCast(rects.len),
        ));
    }
};

// ---------------------------------------------------------------------
// Message boxes
// ---------------------------------------------------------------------

pub const MessageBoxFlags = packed struct(u32) {
    _reserved0: u4 = 0,
    err: bool = false,
    warning: bool = false,
    information: bool = false,
    buttons_left_to_right: bool = false,
    buttons_right_to_left: bool = false,
    _reserved1: u23 = 0,

    pub const error_box: MessageBoxFlags = .{ .err = true };
    pub const warning_box: MessageBoxFlags = .{ .warning = true };
    pub const info_box: MessageBoxFlags = .{ .information = true };
};

/// Blocks until the box is dismissed. Works before `sdl.init`, which is what
/// makes it the right way to report a failure to start.
pub fn showSimpleMessageBox(
    flags: MessageBoxFlags,
    title: [:0]const u8,
    message: [:0]const u8,
    parent: ?Window,
) Error!void {
    try check(raw.SDL_ShowSimpleMessageBox(
        @bitCast(flags),
        title.ptr,
        message.ptr,
        if (parent) |w| w.handle else null,
    ));
}

comptime {
    std.debug.assert(@sizeOf(DisplayMode) == @sizeOf(raw.SDL_DisplayMode));
}
