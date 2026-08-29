//! Opens a window, reports what SDL made of it, and draws until you quit.
//!
//!     zig build run-window
//!     zig build run-window -- --frames 60
const std = @import("std");
const sdl = @import("sdl3");

fn frameLimit(init: std.process.Init) !?u64 {
    var args = init.minimal.args.iterate();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingValue;
            return try std.fmt.parseInt(u64, value, 10);
        }
    }
    return null;
}

pub fn main(init: std.process.Init) !void {
    const limit = try frameLimit(init);

    try sdl.setAppMetadata("sdl3-zig window", "0.1.0", "com.example.sdl3-zig.window");

    sdl.init(.{ .video = true }) catch |err| {
        std.debug.print("init failed: {t} -- {s}\n", .{ err, sdl.lastErrorText() });
        return err;
    };
    defer sdl.quit();

    const both = try sdl.createWindowAndRenderer("sdl3-zig", 960, 540, .{
        .resizable = true,
        .high_pixel_density = true,
    });
    defer both.renderer.deinit();
    defer both.window.deinit();

    const window = both.window;
    const renderer = both.renderer;

    try renderer.setVSync(1);

    const size = try window.size();
    const pixel_size = try window.sizeInPixels();
    std.debug.print(
        "window {d}x{d}, {d}x{d} pixels, density {d:.1}x, renderer \"{s}\"\n",
        .{
            size.width,
            size.height,
            pixel_size.width,
            pixel_size.height,
            window.pixelDensity(),
            renderer.name(),
        },
    );
    std.debug.print("escape or close the window to quit\n", .{});

    var frames: u64 = 0;
    main_loop: while (true) {
        while (sdl.events.poll()) |event| switch (event) {
            .quit => break :main_loop,
            .window => |e| switch (e.kind) {
                .close_requested => break :main_loop,
                // The pixel size, not the screen-coordinate size, is what a
                // renderer has to react to.
                .pixel_size_changed => |new_size| std.debug.print(
                    "framebuffer now {d}x{d}\n",
                    .{ new_size.width, new_size.height },
                ),
                else => {},
            },
            .key_down => |e| if (e.key == .escape) break :main_loop,
            else => {},
        };

        // A slow sweep through the hues, so it is obvious the loop is live.
        const t = @as(f32, @floatFromInt(frames)) / 240.0;
        try renderer.setDrawColorFloat(.{
            .r = 0.10 + 0.05 * @sin(t),
            .g = 0.11 + 0.05 * @sin(t + 2.1),
            .b = 0.14 + 0.05 * @sin(t + 4.2),
            .a = 1,
        });
        try renderer.clear();

        try renderer.setDrawColor(.rgb(220, 220, 230));
        try renderer.debugText(16, 16, "sdl3-zig");
        try renderer.present();

        frames += 1;
        if (limit) |n| {
            if (frames >= n) break;
        }
    }

    std.debug.print("ran {d} frames\n", .{frames});
}
