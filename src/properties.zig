//! SDL's typed key-value groups.
//!
//! Properties are how SDL 3 passes the options that do not fit a function
//! signature: the extended create-info for a window, a renderer or a texture,
//! and the native handles a backend exposes. A group is an integer id, not a
//! pointer, so `Properties` is a value type.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");

const Error = errors.Error;
const check = errors.check;

pub const PropertyType = enum(c_uint) {
    invalid = raw.SDL_PROPERTY_TYPE_INVALID,
    pointer = raw.SDL_PROPERTY_TYPE_POINTER,
    string = raw.SDL_PROPERTY_TYPE_STRING,
    number = raw.SDL_PROPERTY_TYPE_NUMBER,
    float = raw.SDL_PROPERTY_TYPE_FLOAT,
    boolean = raw.SDL_PROPERTY_TYPE_BOOLEAN,
    _,
};

pub const Properties = struct {
    id: u32,

    /// A group the caller owns and must `deinit`.
    pub fn init() Error!Properties {
        const id = raw.SDL_CreateProperties();
        if (id == 0) return Error.SdlError;
        return .{ .id = id };
    }

    /// Never call this on a group that came from an SDL object -- those are
    /// owned by the object and freed with it.
    pub fn deinit(self: Properties) void {
        raw.SDL_DestroyProperties(self.id);
    }

    /// The process-wide group, for values that outlive any one object.
    pub fn global() Error!Properties {
        const id = raw.SDL_GetGlobalProperties();
        if (id == 0) return Error.SdlError;
        return .{ .id = id };
    }

    pub fn has(self: Properties, name: [:0]const u8) bool {
        return raw.SDL_HasProperty(self.id, name.ptr);
    }

    pub fn typeOf(self: Properties, name: [:0]const u8) PropertyType {
        return @fromBackingInt(@intCast(raw.SDL_GetPropertyType(self.id, name.ptr)));
    }

    pub fn clear(self: Properties, name: [:0]const u8) Error!void {
        try check(raw.SDL_ClearProperty(self.id, name.ptr));
    }

    // -- reads; each takes the value to fall back to ---------------------

    pub fn getNumber(self: Properties, name: [:0]const u8, default_value: i64) i64 {
        return raw.SDL_GetNumberProperty(self.id, name.ptr, default_value);
    }

    pub fn getFloat(self: Properties, name: [:0]const u8, default_value: f32) f32 {
        return raw.SDL_GetFloatProperty(self.id, name.ptr, default_value);
    }

    pub fn getBool(self: Properties, name: [:0]const u8, default_value: bool) bool {
        return raw.SDL_GetBooleanProperty(self.id, name.ptr, default_value);
    }

    /// Borrowed from SDL and valid only until the property is changed. Copy
    /// it if you need to keep it.
    pub fn getString(self: Properties, name: [:0]const u8, default_value: [:0]const u8) []const u8 {
        const text = raw.SDL_GetStringProperty(self.id, name.ptr, default_value.ptr);
        if (text == null) return "";
        return std.mem.span(text);
    }

    /// The native handles SDL exposes come through here: a `CAMetalLayer`, an
    /// `HWND`, a `VkInstance`. The property names are in SDL's headers.
    pub fn getPointer(self: Properties, name: [:0]const u8) ?*anyopaque {
        return raw.SDL_GetPointerProperty(self.id, name.ptr, null);
    }

    // -- writes ----------------------------------------------------------

    pub fn setNumber(self: Properties, name: [:0]const u8, value: i64) Error!void {
        try check(raw.SDL_SetNumberProperty(self.id, name.ptr, value));
    }

    pub fn setFloat(self: Properties, name: [:0]const u8, value: f32) Error!void {
        try check(raw.SDL_SetFloatProperty(self.id, name.ptr, value));
    }

    pub fn setBool(self: Properties, name: [:0]const u8, value: bool) Error!void {
        try check(raw.SDL_SetBooleanProperty(self.id, name.ptr, value));
    }

    /// SDL copies the string.
    pub fn setString(self: Properties, name: [:0]const u8, value: [:0]const u8) Error!void {
        try check(raw.SDL_SetStringProperty(self.id, name.ptr, value.ptr));
    }

    /// SDL stores the pointer and never owns it: it must outlive the group.
    pub fn setPointer(self: Properties, name: [:0]const u8, value: ?*anyopaque) Error!void {
        try check(raw.SDL_SetPointerProperty(self.id, name.ptr, value));
    }

    /// Copies every property that is not a pointer. Pointers are skipped
    /// because SDL cannot know who would own the copy.
    pub fn copyTo(self: Properties, dst: Properties) Error!void {
        try check(raw.SDL_CopyProperties(self.id, dst.id));
    }

    /// Held across a read-modify-write on a group another thread also uses.
    pub fn lock(self: Properties) Error!void {
        try check(raw.SDL_LockProperties(self.id));
    }

    pub fn unlock(self: Properties) void {
        raw.SDL_UnlockProperties(self.id);
    }
};
