//! Draws with the 2D renderer: rectangles, lines, a texture built by hand,
//! and geometry. Also shows logical presentation, which is how you draw at a
//! fixed resolution and let SDL fit it to the window.
//!
//!     zig build run-shapes
//!     zig build run-shapes -- --frames 120
const std = @import("std");
const sdl = @import("sdl3");

const logical_width = 320;
const logical_height = 180;

fn frameLimit(init: std.process.Init) !?u64 {
    const args = try init.minimal.args.toSlice(
        init.arena.allocator(),
    );

    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--frames")) {
            if (i + 1 >= args.len)
                return error.MissingValue;

            return try std.fmt.parseInt(
                u64,
                args[i + 1],
                10,
            );
        }
    }

    return null;
}

/// A 16x16 checkerboard, written a pixel at a time into a streaming texture.
fn makeCheckerboard(renderer: sdl.Renderer) !sdl.Texture {
    const texture = try sdl.Texture.init(renderer, .rgba32, .streaming, 16, 16);
    errdefer texture.deinit();

    // Nearest sampling: this is pixel art, and linear would smear it.
    try texture.setScaleMode(.nearest);

    const locked = try texture.lock(null);
    defer texture.unlock();

    for (0..16) |y| {
        const row = locked.pixels[y * locked.pitch ..][0 .. 16 * 4];
        for (0..16) |x| {
            const light = ((x / 4) + (y / 4)) % 2 == 0;
            const value: u8 = if (light) 235 else 90;
            row[x * 4 + 0] = value;
            row[x * 4 + 1] = value;
            row[x * 4 + 2] = @intCast(120 + x * 8);
            row[x * 4 + 3] = 255;
        }
    }

    return texture;
}

pub fn main(init: std.process.Init) !void {
    const limit = try frameLimit(init);

    sdl.init(.{ .video = true }) catch |err| {
        std.debug.print("init failed: {t} -- {s}\n", .{ err, sdl.lastErrorText() });
        return err;
    };
    defer sdl.quit();

    const both = try sdl.createWindowAndRenderer("sdl3-zig shapes", 960, 540, .{
        .resizable = true,
    });
    defer both.renderer.deinit();
    defer both.window.deinit();

    const renderer = both.renderer;
    try renderer.setVSync(1);

    // Everything below is drawn in a 320x180 space; SDL scales it up by whole
    // numbers and letterboxes the remainder.
    try renderer.setLogicalPresentation(logical_width, logical_height, .integer_scale);

    const checkerboard = try makeCheckerboard(renderer);
    defer checkerboard.deinit();

    var frames: u64 = 0;
    main_loop: while (true) {
        while (sdl.events.poll()) |event| switch (event) {
            .quit => break :main_loop,
            .window => |e| if (e.kind == .close_requested) break :main_loop,
            .key_down => |e| if (e.key == .escape) break :main_loop,
            else => {},
        };

        const t = @as(f32, @floatFromInt(frames)) / 60.0;

        try renderer.setDrawColor(.rgb(18, 18, 24));
        try renderer.clear();

        // A grid, drawn as one call per axis rather than one per line.
        try renderer.setDrawColor(.rgb(32, 32, 44));
        var x: f32 = 0;
        while (x < logical_width) : (x += 20) try renderer.line(x, 0, x, logical_height);
        var y: f32 = 0;
        while (y < logical_height) : (y += 20) try renderer.line(0, y, logical_width, y);

        // Filled rectangles, alpha-blended over the grid.
        try renderer.setDrawBlendMode(.blend);
        try renderer.setDrawColor(.rgba(90, 160, 250, 180));
        try renderer.fillRect(.{ .x = 20, .y = 30, .w = 80, .h = 50 });
        try renderer.setDrawColor(.rgba(250, 120, 90, 180));
        try renderer.fillRect(.{ .x = 60 + 20 * @sin(t), .y = 55, .w = 80, .h = 50 });

        // The texture, rotating about its own centre.
        const dst: sdl.FRect = .{ .x = 200, .y = 40, .w = 64, .h = 64 };
        try renderer.textureRotated(checkerboard, null, dst, t * 40, null, .none);

        // Raw geometry: one triangle with a colour at each corner.
        const vertices = [_]sdl.Vertex{
            .{ .position = .{ .x = 160, .y = 120 }, .color = .{ .r = 1, .g = 0.3, .b = 0.3, .a = 1 } },
            .{ .position = .{ .x = 200, .y = 165 }, .color = .{ .r = 0.3, .g = 1, .b = 0.4, .a = 1 } },
            .{ .position = .{ .x = 120, .y = 165 }, .color = .{ .r = 0.4, .g = 0.5, .b = 1, .a = 1 } },
        };
        try renderer.geometry(null, &vertices, &.{});

        try renderer.setDrawColor(.rgb(230, 230, 240));
        try renderer.debugText(8, 8, "sdl3-zig -- 320x180, integer scaled");
        try renderer.present();

        frames += 1;
        if (limit) |n| {
            if (frames >= n) break;
        }
    }
}
