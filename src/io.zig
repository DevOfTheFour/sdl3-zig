//! `IOStream`, SDL's abstraction over a file, a memory block, or anything
//! else a caller can read and write.
//!
//! Zig has `std.fs` and `std.Io`, and for ordinary file work you should use
//! them. `IOStream` earns its place where an SDL call takes one: loading a
//! BMP or a WAV from memory instead of a path, for instance, or writing a
//! surface into a buffer.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");

const Error = errors.Error;
const check = errors.check;

pub const Whence = enum(c_uint) {
    /// From the beginning.
    set = raw.SDL_IO_SEEK_SET,
    /// From where the stream is now.
    current = raw.SDL_IO_SEEK_CUR,
    /// Backwards from the end.
    end = raw.SDL_IO_SEEK_END,
    _,
};

pub const Status = enum(c_uint) {
    ready = raw.SDL_IO_STATUS_READY,
    err = raw.SDL_IO_STATUS_ERROR,
    eof = raw.SDL_IO_STATUS_EOF,
    /// A non-blocking stream with nothing available yet.
    not_ready = raw.SDL_IO_STATUS_NOT_READY,
    read_only = raw.SDL_IO_STATUS_READONLY,
    write_only = raw.SDL_IO_STATUS_WRITEONLY,
    _,
};

pub const IOStream = struct {
    handle: *raw.SDL_IOStream,

    /// `mode` is stdio's: "rb", "wb", "r+b", and so on.
    pub fn fromFile(path: [:0]const u8, mode: [:0]const u8) Error!IOStream {
        return .{ .handle = try errors.checkPtr(raw.SDL_IOFromFile(path.ptr, mode.ptr)) };
    }

    /// A read-write view of memory the caller owns. The buffer must outlive
    /// the stream.
    pub fn fromMemory(buffer: []u8) Error!IOStream {
        const handle = raw.SDL_IOFromMem(buffer.ptr, buffer.len);
        return .{ .handle = try errors.checkPtr(handle) };
    }

    /// A read-only view. The usual way to hand SDL an asset already in
    /// memory: `Surface.loadBmpFromStream(try IOStream.fromConstMemory(bytes), true)`.
    pub fn fromConstMemory(buffer: []const u8) Error!IOStream {
        const handle = raw.SDL_IOFromConstMem(buffer.ptr, buffer.len);
        return .{ .handle = try errors.checkPtr(handle) };
    }

    /// A stream that grows as it is written. What was written is reachable
    /// through the stream's `SDL_PROP_IOSTREAM_DYNAMIC_MEMORY_POINTER`
    /// property before it is closed.
    pub fn fromDynamicMemory() Error!IOStream {
        return .{ .handle = try errors.checkPtr(raw.SDL_IOFromDynamicMem()) };
    }

    /// Flushes and closes. Fails when the final flush does, so a write stream
    /// is worth `try`ing rather than `defer`ring blind.
    pub fn close(self: IOStream) Error!void {
        try check(raw.SDL_CloseIO(self.handle));
    }

    pub fn status(self: IOStream) Status {
        return @fromBackingInt(@intCast(raw.SDL_GetIOStatus(self.handle)));
    }

    /// Null when the stream does not know its own length -- a pipe, say.
    pub fn size(self: IOStream) ?u64 {
        const value = raw.SDL_GetIOSize(self.handle);
        if (value < 0) return null;
        return @intCast(value);
    }

    pub fn seek(self: IOStream, offset: i64, whence: Whence) Error!u64 {
        const position = raw.SDL_SeekIO(self.handle, offset, @backingInt(whence));
        if (position < 0) return Error.SdlError;
        return @intCast(position);
    }

    pub fn tell(self: IOStream) Error!u64 {
        const position = raw.SDL_TellIO(self.handle);
        if (position < 0) return Error.SdlError;
        return @intCast(position);
    }

    /// Reads up to `buffer.len` bytes. A short read is normal; zero means end
    /// of stream or an error, and `status` says which.
    pub fn read(self: IOStream, buffer: []u8) usize {
        return raw.SDL_ReadIO(self.handle, buffer.ptr, buffer.len);
    }

    /// Returns what was written, which is less than `data.len` only on error.
    pub fn write(self: IOStream, data: []const u8) usize {
        return raw.SDL_WriteIO(self.handle, data.ptr, data.len);
    }

    pub fn flush(self: IOStream) Error!void {
        try check(raw.SDL_FlushIO(self.handle));
    }
};

/// Reads a whole file through SDL. The result is SDL-allocated: free it with
/// `freeFile`, not with a Zig allocator.
///
/// `std.fs.Dir.readFileAlloc` is the better choice for your own files; this
/// one exists for the platforms where SDL's path handling differs from the
/// C library's, notably Android assets.
pub fn loadFile(path: [:0]const u8) Error![]u8 {
    var len: usize = 0;
    const data = try errors.checkPtr(raw.SDL_LoadFile(path.ptr, &len));
    const bytes: [*]u8 = @ptrCast(data);
    return bytes[0..len];
}

pub fn freeFile(data: []u8) void {
    raw.SDL_free(data.ptr);
}

pub fn saveFile(path: [:0]const u8, data: []const u8) Error!void {
    try check(raw.SDL_SaveFile(path.ptr, data.ptr, data.len));
}
