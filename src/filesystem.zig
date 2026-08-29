//! Where a program is allowed to put things, and the few path operations SDL
//! provides for getting there.
//!
//! The two that matter: `basePath` is where the executable lives and is
//! read-only in practice, and `prefPath` is the per-user directory you are
//! meant to write to. Hard-coding either is what breaks an installed build.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");

const Error = errors.Error;
const check = errors.check;

/// The directory the executable was loaded from, with a trailing separator.
/// Owned by SDL; never freed. Null on a platform with no such concept.
pub fn basePath() ?[:0]const u8 {
    const path = raw.SDL_GetBasePath();
    if (path == null) return null;
    return std.mem.span(path);
}

/// The per-user directory for this application's own data, created if it does
/// not exist, with a trailing separator. SDL-allocated: free it with
/// `freePath`.
///
/// `org` and `app` become directory names, so keep them to something a
/// filesystem will accept.
pub fn prefPath(org: [:0]const u8, app: [:0]const u8) Error![:0]u8 {
    const path = try errors.checkPtr(@as(?[*:0]u8, @ptrCast(raw.SDL_GetPrefPath(org.ptr, app.ptr))));
    return std.mem.span(path);
}

pub fn freePath(path: [:0]u8) void {
    raw.SDL_free(path.ptr);
}

/// A directory the user knows by name.
pub const Folder = enum(c_uint) {
    home = raw.SDL_FOLDER_HOME,
    desktop = raw.SDL_FOLDER_DESKTOP,
    documents = raw.SDL_FOLDER_DOCUMENTS,
    downloads = raw.SDL_FOLDER_DOWNLOADS,
    music = raw.SDL_FOLDER_MUSIC,
    pictures = raw.SDL_FOLDER_PICTURES,
    public_share = raw.SDL_FOLDER_PUBLICSHARE,
    saved_games = raw.SDL_FOLDER_SAVEDGAMES,
    screenshots = raw.SDL_FOLDER_SCREENSHOTS,
    templates = raw.SDL_FOLDER_TEMPLATES,
    videos = raw.SDL_FOLDER_VIDEOS,
    _,
};

/// Owned by SDL. Null when the platform has no such folder, which is common
/// for the more exotic ones.
pub fn userFolder(folder: Folder) ?[:0]const u8 {
    const path = raw.SDL_GetUserFolder(@backingInt(folder));
    if (path == null) return null;
    return std.mem.span(path);
}

/// SDL-allocated: free it with `freePath`.
pub fn currentDirectory() Error![:0]u8 {
    const path = try errors.checkPtr(@as(?[*:0]u8, @ptrCast(raw.SDL_GetCurrentDirectory())));
    return std.mem.span(path);
}

pub const PathType = enum(c_uint) {
    /// Nothing is there.
    none = raw.SDL_PATHTYPE_NONE,
    file = raw.SDL_PATHTYPE_FILE,
    directory = raw.SDL_PATHTYPE_DIRECTORY,
    /// A device, a socket, something else.
    other = raw.SDL_PATHTYPE_OTHER,
    _,
};

/// Layout-compatible with `SDL_PathInfo`. Times are nanoseconds since the
/// Unix epoch.
pub const PathInfo = extern struct {
    type: PathType = .none,
    size: u64 = 0,
    create_time: i64 = 0,
    modify_time: i64 = 0,
    access_time: i64 = 0,
};

pub fn pathInfo(path: [:0]const u8) Error!PathInfo {
    var info: PathInfo = .{};
    try check(raw.SDL_GetPathInfo(path.ptr, @ptrCast(&info)));
    return info;
}

pub fn exists(path: [:0]const u8) bool {
    var info: raw.SDL_PathInfo = undefined;
    return raw.SDL_GetPathInfo(path.ptr, &info);
}

/// Creates the directory and any missing parents.
pub fn createDirectory(path: [:0]const u8) Error!void {
    try check(raw.SDL_CreateDirectory(path.ptr));
}

/// Removes an empty directory or a file. Fails on a directory that still has
/// anything in it.
pub fn removePath(path: [:0]const u8) Error!void {
    try check(raw.SDL_RemovePath(path.ptr));
}

pub fn renamePath(old_path: [:0]const u8, new_path: [:0]const u8) Error!void {
    try check(raw.SDL_RenamePath(old_path.ptr, new_path.ptr));
}

pub fn copyFile(old_path: [:0]const u8, new_path: [:0]const u8) Error!void {
    try check(raw.SDL_CopyFile(old_path.ptr, new_path.ptr));
}

/// What an enumeration callback returns to say what should happen next.
pub const EnumerateResult = enum(c_uint) {
    /// Keep going.
    @"continue" = raw.SDL_ENUM_CONTINUE,
    /// Stop here; the enumeration succeeded.
    success = raw.SDL_ENUM_SUCCESS,
    /// Stop here; the enumeration failed.
    failure = raw.SDL_ENUM_FAILURE,
    _,
};

pub const EnumerateCallback = *const fn (
    userdata: ?*anyopaque,
    directory: [*c]const u8,
    name: [*c]const u8,
) callconv(.c) EnumerateResult;

/// Calls `callback` once per entry. Not recursive: a callback that wants to
/// descend calls `enumerateDirectory` again on the child.
///
/// The callback runs on this thread, but it runs from C, so it must not
/// return an error or panic.
pub fn enumerateDirectory(
    path: [:0]const u8,
    callback: EnumerateCallback,
    userdata: ?*anyopaque,
) Error!void {
    try check(raw.SDL_EnumerateDirectory(path.ptr, @ptrCast(callback), userdata));
}

/// Every entry matching a shell-style pattern such as `"*.png"`. The result
/// is one SDL allocation holding both the pointers and the strings, so
/// `deinit` frees the lot.
pub const Glob = struct {
    entries: []const [*:0]u8,

    pub fn next(self: *Glob, index: *usize) ?[:0]const u8 {
        if (index.* == self.entries.len) return null;
        defer index.* += 1;
        return std.mem.span(self.entries[index.*]);
    }

    pub fn get(self: Glob, index: usize) [:0]const u8 {
        return std.mem.span(self.entries[index]);
    }

    pub fn count(self: Glob) usize {
        return self.entries.len;
    }

    pub fn deinit(self: Glob) void {
        raw.SDL_free(@ptrCast(@constCast(self.entries.ptr)));
    }
};

/// `pattern` null matches everything.
pub fn globDirectory(path: [:0]const u8, pattern: ?[:0]const u8) Error!Glob {
    var count: c_int = 0;
    const list = raw.SDL_GlobDirectory(
        path.ptr,
        if (pattern) |p| p.ptr else null,
        0,
        &count,
    );
    const entries = try errors.checkPtr(@as(?[*]const [*:0]u8, @ptrCast(list)));
    return .{ .entries = entries[0..@intCast(count)] };
}
