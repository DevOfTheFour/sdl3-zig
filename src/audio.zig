//! Audio devices and streams.
//!
//! SDL 3 puts a resampling stream between you and the device, so the format
//! you feed in has nothing to do with the format the hardware wants. The
//! short path is `Stream.openDevice`: it opens the default device, makes a
//! stream in *your* format, and binds the two.
//!
//! Audio runs on SDL's own thread. A callback set here is called from it, and
//! anything it touches must be safe to touch from another thread.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const io_mod = @import("io.zig");

const Error = errors.Error;
const check = errors.check;

pub const DeviceId = u32;

/// Sample format. The `le`/`be` names pin the byte order; the unsuffixed ones
/// follow the machine, and are what you want for samples you generate.
pub const Format = enum(c_uint) {
    unknown = raw.SDL_AUDIO_UNKNOWN,
    u8 = raw.SDL_AUDIO_U8,
    s8 = raw.SDL_AUDIO_S8,
    s16le = raw.SDL_AUDIO_S16LE,
    s16be = raw.SDL_AUDIO_S16BE,
    s32le = raw.SDL_AUDIO_S32LE,
    s32be = raw.SDL_AUDIO_S32BE,
    f32le = raw.SDL_AUDIO_F32LE,
    f32be = raw.SDL_AUDIO_F32BE,
    _,

    /// The machine's own byte order, which is what samples you generate
    /// yourself are already in.
    pub const s16_native: Format = @fromBackingInt(@intCast(raw.SDL_AUDIO_S16));
    pub const s32_native: Format = @fromBackingInt(@intCast(raw.SDL_AUDIO_S32));
    /// What SDL mixes in internally, and the format with no conversion cost.
    pub const f32_native: Format = @fromBackingInt(@intCast(raw.SDL_AUDIO_F32));

    pub fn bytesPerSample(self: Format) u8 {
        return @intCast((@backingInt(self) & raw.SDL_AUDIO_MASK_BITSIZE) / 8);
    }

    pub fn isFloat(self: Format) bool {
        return (@backingInt(self) & raw.SDL_AUDIO_MASK_FLOAT) != 0;
    }

    pub fn isSigned(self: Format) bool {
        return (@backingInt(self) & raw.SDL_AUDIO_MASK_SIGNED) != 0;
    }

    /// SDL's name, such as "SDL_AUDIO_F32LE". Owned by SDL.
    pub fn name(self: Format) []const u8 {
        const text = raw.SDL_GetAudioFormatName(@backingInt(self));
        if (text == null) return "";
        return std.mem.span(text);
    }
};

/// Layout-compatible with `SDL_AudioSpec`.
pub const Spec = extern struct {
    format: Format = Format.f32_native,
    channels: c_int = 2,
    /// Sample frames per second.
    freq: c_int = 48000,

    /// Bytes in one sample frame: one sample per channel.
    pub fn frameSize(self: Spec) usize {
        return @as(usize, self.format.bytesPerSample()) * @as(usize, @intCast(self.channels));
    }
};

pub fn driverCount() usize {
    const count = raw.SDL_GetNumAudioDrivers();
    return if (count < 0) 0 else @intCast(count);
}

pub fn driverName(index: usize) ?[]const u8 {
    const text = raw.SDL_GetAudioDriver(@intCast(index));
    if (text == null) return null;
    return std.mem.span(text);
}

pub const Device = struct {
    id: DeviceId,

    /// The device the user has chosen in the OS, which is also the one that
    /// follows them when they change it.
    pub const default_playback: Device = .{ .id = raw.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK };
    pub const default_recording: Device = .{ .id = raw.SDL_AUDIO_DEVICE_DEFAULT_RECORDING };

    /// Every playback device. The slice is SDL's; free it with `freeIds`.
    pub fn playbackDevices() Error![]const DeviceId {
        var count: c_int = 0;
        const list = try errors.checkPtr(@as(?[*]DeviceId, raw.SDL_GetAudioPlaybackDevices(&count)));
        return list[0..@intCast(count)];
    }

    pub fn recordingDevices() Error![]const DeviceId {
        var count: c_int = 0;
        const list = try errors.checkPtr(@as(?[*]DeviceId, raw.SDL_GetAudioRecordingDevices(&count)));
        return list[0..@intCast(count)];
    }

    pub fn freeIds(list: []const DeviceId) void {
        raw.SDL_free(@ptrCast(@constCast(list.ptr)));
    }

    /// Owned by SDL.
    pub fn name(self: Device) []const u8 {
        const text = raw.SDL_GetAudioDeviceName(self.id);
        if (text == null) return "";
        return std.mem.span(text);
    }

    /// Opens a *logical* device. Several can be open on one physical device,
    /// and each has its own streams and its own pause state.
    ///
    /// `spec` is a request, not a promise: SDL resamples whatever the streams
    /// bound to it produce. Pass null to take the hardware's own format.
    pub fn open(self: Device, spec: ?Spec) Error!Device {
        const spec_ptr: [*c]const raw.SDL_AudioSpec = if (spec) |s| @ptrCast(&s) else null;
        const id = raw.SDL_OpenAudioDevice(self.id, spec_ptr);
        if (id == 0) return Error.SdlError;
        return .{ .id = id };
    }

    pub fn close(self: Device) void {
        raw.SDL_CloseAudioDevice(self.id);
    }

    /// What the device is actually running at, and how many sample frames it
    /// asks for at a time.
    pub fn format(self: Device) Error!struct { spec: Spec, sample_frames: i32 } {
        var spec: Spec = .{};
        var frames: c_int = 0;
        try check(raw.SDL_GetAudioDeviceFormat(self.id, @ptrCast(&spec), &frames));
        return .{ .spec = spec, .sample_frames = frames };
    }

    /// A device opened with `open` starts paused, so this is the call that
    /// starts the sound.
    pub fn play(self: Device) Error!void {
        try check(raw.SDL_ResumeAudioDevice(self.id));
    }

    pub fn pause(self: Device) Error!void {
        try check(raw.SDL_PauseAudioDevice(self.id));
    }

    pub fn paused(self: Device) bool {
        return raw.SDL_AudioDevicePaused(self.id);
    }

    /// 1.0 is unchanged. Applies to everything bound to this logical device.
    pub fn setGain(self: Device, value: f32) Error!void {
        try check(raw.SDL_SetAudioDeviceGain(self.id, value));
    }

    pub fn gain(self: Device) f32 {
        return raw.SDL_GetAudioDeviceGain(self.id);
    }

    pub fn bind(self: Device, stream: Stream) Error!void {
        try check(raw.SDL_BindAudioStream(self.id, stream.handle));
    }
};

/// A resampling queue between your samples and a device.
pub const Stream = struct {
    handle: *raw.SDL_AudioStream,

    /// SDL calls this when the stream needs more data (playback) or has data
    /// waiting (recording). `additional` is what SDL wants right now;
    /// `total` is everything queued. Runs on the audio thread.
    pub const Callback = *const fn (
        userdata: ?*anyopaque,
        stream: ?*raw.SDL_AudioStream,
        additional: c_int,
        total: c_int,
    ) callconv(.c) void;

    /// The short path: opens `device`, creates a stream in `spec`, binds
    /// them, and hands the stream back. The device is still paused -- call
    /// `play` on the stream when you are ready.
    ///
    /// A null `callback` means you push samples yourself with `put`.
    pub fn openDevice(
        target: Device,
        spec: Spec,
        callback: ?Callback,
        userdata: ?*anyopaque,
    ) Error!Stream {
        const handle = raw.SDL_OpenAudioDeviceStream(
            target.id,
            @ptrCast(&spec),
            @ptrCast(callback),
            userdata,
        );
        return .{ .handle = try errors.checkPtr(handle) };
    }

    /// A stream not bound to anything, for converting between two formats.
    pub fn init(src: Spec, dst: Spec) Error!Stream {
        const handle = raw.SDL_CreateAudioStream(@ptrCast(&src), @ptrCast(&dst));
        return .{ .handle = try errors.checkPtr(handle) };
    }

    /// Unbinds and destroys. Does not close the device it was bound to.
    pub fn deinit(self: Stream) void {
        raw.SDL_DestroyAudioStream(self.handle);
    }

    /// The device this stream feeds, for a stream from `openDevice`.
    pub fn device(self: Stream) Device {
        return .{ .id = raw.SDL_GetAudioStreamDevice(self.handle) };
    }

    /// Resumes the device this stream is bound to.
    pub fn play(self: Stream) Error!void {
        try check(raw.SDL_ResumeAudioStreamDevice(self.handle));
    }

    pub fn pause(self: Stream) Error!void {
        try check(raw.SDL_PauseAudioStreamDevice(self.handle));
    }

    /// Queues samples in the stream's input format. SDL copies them, so the
    /// buffer can be reused straight away.
    pub fn put(self: Stream, data: []const u8) Error!void {
        try check(raw.SDL_PutAudioStreamData(self.handle, data.ptr, @intCast(data.len)));
    }

    /// Pulls converted samples out. Returns how many bytes were written,
    /// which may be less than asked for.
    pub fn get(self: Stream, buffer: []u8) Error!usize {
        const count = raw.SDL_GetAudioStreamData(self.handle, buffer.ptr, @intCast(buffer.len));
        if (count < 0) return Error.SdlError;
        return @intCast(count);
    }

    /// Bytes ready to come out, in the output format.
    pub fn available(self: Stream) usize {
        const count = raw.SDL_GetAudioStreamAvailable(self.handle);
        return if (count < 0) 0 else @intCast(count);
    }

    /// Bytes still waiting to be converted, in the input format. This is the
    /// number to watch to keep a queue from running dry or growing forever.
    pub fn queued(self: Stream) usize {
        const count = raw.SDL_GetAudioStreamQueued(self.handle);
        return if (count < 0) 0 else @intCast(count);
    }

    /// Tells the stream no more input is coming, so it can emit the tail it
    /// was holding back for resampling.
    pub fn flush(self: Stream) Error!void {
        try check(raw.SDL_FlushAudioStream(self.handle));
    }

    /// Throws away everything queued, both sides.
    pub fn clear(self: Stream) Error!void {
        try check(raw.SDL_ClearAudioStream(self.handle));
    }

    pub fn setFormat(self: Stream, src: ?Spec, dst: ?Spec) Error!void {
        const src_ptr: [*c]const raw.SDL_AudioSpec = if (src) |s| @ptrCast(&s) else null;
        const dst_ptr: [*c]const raw.SDL_AudioSpec = if (dst) |s| @ptrCast(&s) else null;
        try check(raw.SDL_SetAudioStreamFormat(self.handle, src_ptr, dst_ptr));
    }

    /// 1.0 is unchanged. Per-stream, so this is the volume knob for one sound
    /// rather than for the device.
    pub fn setGain(self: Stream, value: f32) Error!void {
        try check(raw.SDL_SetAudioStreamGain(self.handle, value));
    }

    pub fn gain(self: Stream) f32 {
        return raw.SDL_GetAudioStreamGain(self.handle);
    }

    /// Plays faster or slower without changing the format: 2.0 is double
    /// speed, and pitch rises with it.
    pub fn setFrequencyRatio(self: Stream, ratio: f32) Error!void {
        try check(raw.SDL_SetAudioStreamFrequencyRatio(self.handle, ratio));
    }

    /// Called when the stream wants more input. This is the pull-based path;
    /// `put` is the push-based one.
    pub fn setGetCallback(self: Stream, callback: ?Callback, userdata: ?*anyopaque) Error!void {
        try check(raw.SDL_SetAudioStreamGetCallback(self.handle, @ptrCast(callback), userdata));
    }

    pub fn unbind(self: Stream) void {
        raw.SDL_UnbindAudioStream(self.handle);
    }
};

/// A decoded WAV file: SDL-allocated samples plus the format they are in.
pub const Wav = struct {
    spec: Spec,
    /// Free with `deinit`, not with a Zig allocator.
    data: []u8,

    pub fn load(path: [:0]const u8) Error!Wav {
        var spec: Spec = .{};
        var buffer: [*c]u8 = null;
        var len: u32 = 0;
        try check(raw.SDL_LoadWAV(path.ptr, @ptrCast(&spec), &buffer, &len));
        return .{ .spec = spec, .data = buffer[0..len] };
    }

    /// From an already-open stream -- a WAV embedded in an archive, say.
    /// `close_stream` hands the stream to SDL to close.
    pub fn loadFromStream(stream: io_mod.IOStream, close_stream: bool) Error!Wav {
        var spec: Spec = .{};
        var buffer: [*c]u8 = null;
        var len: u32 = 0;
        try check(raw.SDL_LoadWAV_IO(stream.handle, close_stream, @ptrCast(&spec), &buffer, &len));
        return .{ .spec = spec, .data = buffer[0..len] };
    }

    pub fn deinit(self: Wav) void {
        raw.SDL_free(self.data.ptr);
    }

    /// How long it plays for, in seconds.
    pub fn duration(self: Wav) f64 {
        const frame_size = self.spec.frameSize();
        if (frame_size == 0 or self.spec.freq == 0) return 0;
        const frames = self.data.len / frame_size;
        return @as(f64, @floatFromInt(frames)) / @as(f64, @floatFromInt(self.spec.freq));
    }
};

/// Adds `src` into `dst` at `volume`, saturating rather than wrapping. Both
/// must already be in `format`; this does not convert.
pub fn mix(dst: []u8, src: []const u8, format: Format, volume: f32) Error!void {
    std.debug.assert(dst.len >= src.len);
    try check(raw.SDL_MixAudio(dst.ptr, src.ptr, @backingInt(format), @intCast(src.len), volume));
}

comptime {
    std.debug.assert(@sizeOf(Spec) == @sizeOf(raw.SDL_AudioSpec));
}
