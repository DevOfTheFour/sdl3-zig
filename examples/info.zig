//! Reports what SDL found on this machine. Opens no window, so it runs
//! anywhere.
//!
//!     zig build run-info
const std = @import("std");
const sdl = @import("sdl3");

pub fn main(init: std.process.Init) !void {
    _ = init;

    std.debug.print("SDL {f} ({s})\n", .{ sdl.version(), sdl.platform() });
    std.debug.print("{d} logical cores, {d} MiB RAM\n\n", .{
        sdl.logicalCpuCores(),
        sdl.systemRam(),
    });

    std.debug.print("video drivers:  ", .{});
    for (0..sdl.video.driverCount()) |i| {
        std.debug.print("{s} ", .{sdl.video.driverName(i) orelse "?"});
    }
    std.debug.print("\naudio drivers:  ", .{});
    for (0..sdl.audio.driverCount()) |i| {
        std.debug.print("{s} ", .{sdl.audio.driverName(i) orelse "?"});
    }
    std.debug.print("\nrender drivers: ", .{});
    for (0..sdl.render.driverCount()) |i| {
        std.debug.print("{s} ", .{sdl.render.driverName(i) orelse "?"});
    }
    std.debug.print("\ngpu drivers:    ", .{});
    for (0..sdl.gpu.driverCount()) |i| {
        std.debug.print("{s} ", .{sdl.gpu.driverName(i) orelse "?"});
    }
    std.debug.print("\n\n", .{});

    // Everything past here needs a video subsystem, which a headless machine
    // will not give us. That is a fine reason to stop, not a crash.
    sdl.init(.{ .video = true, .audio = true }) catch {
        std.debug.print("no video subsystem here: {s}\n", .{sdl.lastErrorText()});
        return;
    };
    defer sdl.quit();

    std.debug.print("using video driver \"{s}\"\n", .{sdl.video.currentDriver() orelse "none"});

    const displays = try sdl.Display.all();
    defer sdl.Display.freeDisplays(displays);

    for (displays) |id| {
        const display: sdl.Display = .{ .id = id };
        const mode = try display.desktopMode();
        const bounds = try display.bounds();
        std.debug.print(
            "display {d}: {s} -- {d}x{d} @ {d:.0}Hz, scale {d:.2}, at ({d}, {d})\n",
            .{
                id,
                display.name(),
                mode.w,
                mode.h,
                mode.refresh_rate,
                display.contentScale(),
                bounds.x,
                bounds.y,
            },
        );

        var modes = try display.fullscreenModes();
        defer modes.deinit();
        std.debug.print("  {d} fullscreen modes\n", .{modes.count()});
    }

    const playback = sdl.audio.Device.playbackDevices() catch &.{};
    defer if (playback.len > 0) sdl.audio.Device.freeIds(playback);
    for (playback) |id| {
        const audio_device: sdl.audio.Device = .{ .id = id };
        std.debug.print("audio out: {s}\n", .{audio_device.name()});
    }

    if (sdl.gamepad.connectedIds()) |pads| {
        defer sdl.gamepad.freeIds(pads);
        for (pads) |id| {
            const pad = sdl.Gamepad.init(id) catch continue;
            defer pad.deinit();
            std.debug.print("gamepad:   {s} ({t})\n", .{ pad.name(), pad.kind() });
        }
    } else |_| {}
}
