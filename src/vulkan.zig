//! SDL's Vulkan surface helpers, behind `-Dvulkan`.
//!
//! SDL loads Vulkan itself and never links it, so this composes with a
//! dynamic loader such as [vk-zig](https://github.com/zmscode/vk-zig)'s
//! rather than competing with it. The handles here are the raw Vulkan ones,
//! so they pass straight to any Vulkan binding.

const std = @import("std");
const raw = @import("sdl3_raw");
const build_options = @import("sdl3_build_options");
const errors = @import("errors.zig");
const video_mod = @import("video.zig");

const Error = errors.Error;
const check = errors.check;

pub const module = if (build_options.vulkan) struct {
    pub const enabled = true;

    pub const Instance = raw.VkInstance;
    pub const PhysicalDevice = raw.VkPhysicalDevice;
    pub const Surface = raw.VkSurfaceKHR;
    pub const AllocationCallbacks = raw.VkAllocationCallbacks;

    /// Loads the Vulkan loader. `path` null takes the platform default, which
    /// is what you want unless you are shipping your own loader.
    ///
    /// Not needed before `Window.init` with `.vulkan = true` -- SDL loads the
    /// library itself there. Call this only to load it early, or to point at
    /// a specific one.
    pub fn loadLibrary(path: ?[:0]const u8) Error!void {
        try check(raw.SDL_Vulkan_LoadLibrary(if (path) |p| p.ptr else null));
    }

    pub fn unloadLibrary() void {
        raw.SDL_Vulkan_UnloadLibrary();
    }

    /// `vkGetInstanceProcAddr` from the loader SDL opened. This is the entry
    /// point a dynamic Vulkan binding bootstraps from.
    pub fn getInstanceProcAddr() Error!*const anyopaque {
        const address = raw.SDL_Vulkan_GetVkGetInstanceProcAddr();
        if (address == null) return Error.SdlError;
        return @ptrCast(address.?);
    }

    /// The instance extensions a surface needs on this platform. Borrowed
    /// from SDL and valid for the life of the process.
    pub fn instanceExtensions() Error![]const [*:0]const u8 {
        var count: u32 = 0;
        const list = raw.SDL_Vulkan_GetInstanceExtensions(&count);
        if (list == null) return Error.SdlError;
        const names: [*]const [*:0]const u8 = @ptrCast(list);
        return names[0..count];
    }

    /// Iterates the same names as slices.
    pub const ExtensionIterator = struct {
        names: []const [*:0]const u8,
        index: usize = 0,

        pub fn next(self: *ExtensionIterator) ?[:0]const u8 {
            if (self.index == self.names.len) return null;
            defer self.index += 1;
            return std.mem.span(self.names[self.index]);
        }

        pub fn count(self: ExtensionIterator) usize {
            return self.names.len;
        }
    };

    pub fn requiredInstanceExtensions() Error!ExtensionIterator {
        return .{ .names = try instanceExtensions() };
    }

    /// Appends SDL's required extension names to a set with an `append`-shaped
    /// method -- vk-zig's `ExtensionSet`, for instance.
    pub fn appendRequiredInstanceExtensions(set: anytype) !void {
        var it = try requiredInstanceExtensions();
        while (it.next()) |name| try set.append(name);
    }

    /// Creates a surface for `window`, which must have been created with
    /// `.vulkan = true`. The caller owns it: destroy it with
    /// `destroySurface` before the instance.
    pub fn createSurface(
        instance: Instance,
        window: video_mod.Window,
        allocator: ?*const AllocationCallbacks,
    ) Error!Surface {
        var surface: Surface = null;
        try check(raw.SDL_Vulkan_CreateSurface(window.handle, instance, allocator, &surface));
        return surface;
    }

    pub fn destroySurface(
        instance: Instance,
        surface: Surface,
        allocator: ?*const AllocationCallbacks,
    ) void {
        raw.SDL_Vulkan_DestroySurface(instance, surface, allocator);
    }

    /// Whether a queue family can present to this platform's window system.
    /// Ask before choosing a graphics queue, not after.
    pub fn presentationSupport(
        instance: Instance,
        device: PhysicalDevice,
        queue_family: u32,
    ) bool {
        return raw.SDL_Vulkan_GetPresentationSupport(instance, device, queue_family);
    }
} else struct {
    /// Build with `-Dvulkan` to get the rest of this namespace.
    pub const enabled = false;
};
