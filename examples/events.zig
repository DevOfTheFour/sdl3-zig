//! Prints every event as it arrives, which is the quickest way to see what
//! the wrapper turns SDL's union into.
//!
//!     zig build run-events
//!     zig build run-events -- --seconds 5
const std = @import("std");
const sdl = @import("sdl3");

fn secondsLimit(init: std.process.Init) !?u64 {
    var args = init.minimal.args.iterate();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--seconds")) {
            const value = args.next() orelse return error.MissingValue;
            return try std.fmt.parseInt(u64, value, 10);
        }
    }
    return null;
}

/// `Scancode` and `Keycode` are non-exhaustive, so a key SDL sends that the
/// enum does not name is representable -- and `{t}` panics on exactly that.
fn keyName(comptime T: type, value: T) []const u8 {
    return std.enums.tagName(T, value) orelse "unnamed";
}

pub fn main(init: std.process.Init) !void {
    const limit = try secondsLimit(init);

    sdl.init(.{ .video = true, .gamepad = true }) catch |err| {
        std.debug.print("init failed: {t} -- {s}\n", .{ err, sdl.lastErrorText() });
        return err;
    };
    defer sdl.quit();

    const window = try sdl.Window.init("sdl3-zig events", 640, 360, .{ .resizable = true });
    defer window.deinit();

    try sdl.keyboard.startTextInput(window);

    std.debug.print("type, click, scroll, resize, drop a file. escape quits.\n", .{});

    const started = sdl.timer.ticks();
    var open_gamepads: std.ArrayList(sdl.Gamepad) = .empty;
    defer {
        for (open_gamepads.items) |pad| pad.deinit();
        open_gamepads.deinit(init.gpa);
    }

    main_loop: while (true) {
        // Blocking with a timeout keeps the loop responsive without spinning.
        while (sdl.events.waitTimeout(100)) |event| switch (event) {
            .quit => break :main_loop,
            .window => |e| switch (e.kind) {
                .close_requested => break :main_loop,
                .resized => |size| std.debug.print(
                    "window resized to {d}x{d}\n",
                    .{ size.width, size.height },
                ),
                .focus_gained => std.debug.print("focus gained\n", .{}),
                .focus_lost => std.debug.print("focus lost\n", .{}),
                else => std.debug.print("window {t}\n", .{e.kind}),
            },

            .key_down => |e| {
                if (e.key == .escape) break :main_loop;
                std.debug.print("key down  {s} ({s}){s}{s}\n", .{
                    keyName(sdl.Scancode, e.scancode),
                    keyName(sdl.Keycode, e.key),
                    if (e.mod.ctrl()) " +ctrl" else "",
                    if (e.repeat) " (repeat)" else "",
                });
            },
            .key_up => |e| std.debug.print("key up    {s}\n", .{keyName(sdl.Scancode, e.scancode)}),
            .text_input => |e| std.debug.print("text      \"{s}\"\n", .{e.text}),

            .mouse_button_down => |e| std.debug.print(
                "click     {s} x{d} at ({d:.0}, {d:.0})\n",
                .{ keyName(sdl.mouse.Button, e.button), e.clicks, e.x, e.y },
            ),
            .mouse_wheel => |e| std.debug.print(
                "wheel     ({d:.2}, {d:.2})\n",
                .{ e.x, e.y },
            ),

            .gamepad_added => |e| {
                const pad = sdl.Gamepad.init(e.which) catch continue;
                try open_gamepads.append(init.gpa, pad);
                std.debug.print("gamepad   \"{s}\" connected\n", .{pad.name()});
            },
            .gamepad_button_down => |e| std.debug.print(
                "pad down  {s}\n",
                .{keyName(sdl.gamepad.Button, e.button)},
            ),

            .drop_file => |e| std.debug.print("dropped   {s}\n", .{e.data orelse "(nothing)"}),

            else => {},
        };

        if (limit) |seconds| {
            if (sdl.timer.ticks() - started >= seconds * 1000) break;
        }
    }
}
