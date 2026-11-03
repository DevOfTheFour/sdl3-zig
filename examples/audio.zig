//! Plays a tone through an audio stream, or a WAV file if you name one.
//!
//!     zig build run-audio
//!     zig build run-audio -- --seconds 2
//!     zig build run-audio -- path/to/sound.wav
const std = @import("std");
const sdl = @import("sdl3");

const sample_rate = 48_000;
const tone_hz = 220.0;

const Args = struct {
    path: ?[]const u8 = null,
    seconds: u64 = 2,
};

fn parseArgs(init: std.process.Init) !Args {
    const argv = try init.minimal.args.toSlice(
        init.arena.allocator(),
    );

    var result: Args = .{};
    var i: usize = 1;

    while (i < argv.len) : (i += 1) {
        const arg = argv[i];

        if (std.mem.eql(u8, arg, "--seconds")) {
            i += 1;

            if (i >= argv.len)
                return error.MissingValue;

            result.seconds = try std.fmt.parseInt(
                u64,
                argv[i],
                10,
            );
        } else {
            result.path = arg;
        }
    }

    return result;
}

/// A quarter-second of sine, which loops seamlessly because the period
/// divides evenly into the buffer.
fn makeTone(gpa: std.mem.Allocator) ![]f32 {
    const frames = sample_rate / 4;
    const samples = try gpa.alloc(f32, frames);
    for (samples, 0..) |*sample, i| {
        const phase = 2.0 * std.math.pi * tone_hz * @as(f32, @floatFromInt(i)) / sample_rate;
        // Quiet on purpose: this goes straight to the user's speakers.
        sample.* = 0.12 * @sin(phase);
    }
    return samples;
}

pub fn main(init: std.process.Init) !void {
    const args = try parseArgs(init);

    sdl.init(.{ .audio = true }) catch |err| {
        std.debug.print("init failed: {t} -- {s}\n", .{ err, sdl.lastErrorText() });
        return err;
    };
    defer sdl.quit();

    std.debug.print("audio driver \"{s}\"\n", .{sdl.audio.driverName(0) orelse "?"});

    if (args.path) |path| {
        // A WAV plays in whatever format it was recorded in; the stream
        // converts it to whatever the device wants.
        const path_z = try init.gpa.allocSentinel(u8, path.len, 0);
        defer init.gpa.free(path_z);
        @memcpy(path_z, path);

        const wav = try sdl.audio.Wav.load(path_z);
        defer wav.deinit();

        std.debug.print("{s}: {s}, {d} channels, {d} Hz, {d:.2}s\n", .{
            path,
            wav.spec.format.name(),
            wav.spec.channels,
            wav.spec.freq,
            wav.duration(),
        });

        const stream = try sdl.audio.Stream.openDevice(
            .default_playback,
            wav.spec,
            null,
            null,
        );
        defer stream.deinit();

        try stream.put(wav.data);
        try stream.play();

        // Wait for the queue to drain rather than for a fixed time, so the
        // tail is not cut off.
        while (stream.queued() > 0) sdl.timer.delay(20);
        sdl.timer.delay(200);
        return;
    }

    const spec: sdl.audio.Spec = .{
        .format = sdl.audio.Format.f32_native,
        .channels = 1,
        .freq = sample_rate,
    };

    const stream = try sdl.audio.Stream.openDevice(.default_playback, spec, null, null);
    defer stream.deinit();

    const device_format = try stream.device().format();
    std.debug.print("device runs at {s}, {d} channels, {d} Hz\n", .{
        device_format.spec.format.name(),
        device_format.spec.channels,
        device_format.spec.freq,
    });

    const tone = try makeTone(init.gpa);
    defer init.gpa.free(tone);
    const tone_bytes = std.mem.sliceAsBytes(tone);

    try stream.play();
    std.debug.print("playing {d} Hz for {d}s\n", .{ @as(u32, tone_hz), args.seconds });

    const deadline = sdl.timer.ticks() + args.seconds * 1000;
    while (sdl.timer.ticks() < deadline) {
        // Keep roughly half a second queued: enough that a hitch does not
        // starve the device, little enough that stopping is responsive.
        if (stream.queued() < tone_bytes.len * 2) {
            try stream.put(tone_bytes);
        }
        sdl.timer.delay(10);
    }
}
