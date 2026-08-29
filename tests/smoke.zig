const std = @import("std");
const sdl = @import("sdl3");

/// Zig analyses a declaration only where it is used, so walking the namespace
/// tree is what forces the whole wrapper through the compiler rather than only
/// the parts the tests below call. `raw` is skipped: it is 14k lines of
/// translated C, and nothing in it is ours to catch.
fn refAll(comptime T: type, comptime depth: u8) void {
    if (depth == 0) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (comptime std.mem.eql(u8, decl, "raw")) continue;
        const field = @field(T, decl);
        if (@TypeOf(field) == type) {
            switch (@typeInfo(field)) {
                .@"struct", .@"enum", .@"union" => refAll(field, depth - 1),
                else => {},
            }
        }
    }
    std.testing.refAllDecls(T);
}

test "reference every public declaration" {
    @setEvalBranchQuota(200_000);
    refAll(sdl, 4);
}

// ---------------------------------------------------------------------
// Things that hold before init
// ---------------------------------------------------------------------

test "the linked SDL is the one we built" {
    const v = sdl.version();
    try std.testing.expectEqual(@as(u32, 3), v.major);
    try std.testing.expect(sdl.platform().len > 0);
    try std.testing.expect(sdl.revision().len > 0);
}

test "init flags match the C constants" {
    try std.testing.expectEqual(
        sdl.raw.SDL_INIT_VIDEO,
        @as(u32, @bitCast(sdl.InitFlags{ .video = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_INIT_AUDIO,
        @as(u32, @bitCast(sdl.InitFlags{ .audio = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_INIT_GAMEPAD,
        @as(u32, @bitCast(sdl.InitFlags{ .gamepad = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_INIT_VIDEO | sdl.raw.SDL_INIT_EVENTS,
        @as(u32, @bitCast(sdl.InitFlags{ .video = true, .events = true })),
    );
    try std.testing.expectEqual(@as(u32, 0), @as(u32, @bitCast(sdl.InitFlags{})));
}

test "window flags match the C constants" {
    try std.testing.expectEqual(
        sdl.raw.SDL_WINDOW_FULLSCREEN,
        @as(u64, @bitCast(sdl.WindowFlags{ .fullscreen = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_WINDOW_RESIZABLE,
        @as(u64, @bitCast(sdl.WindowFlags{ .resizable = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_WINDOW_HIGH_PIXEL_DENSITY,
        @as(u64, @bitCast(sdl.WindowFlags{ .high_pixel_density = true })),
    );
    // The flags past bit 21 sit on the far side of a reserved gap, which is
    // exactly where a hand-written packed struct goes wrong.
    try std.testing.expectEqual(
        sdl.raw.SDL_WINDOW_VULKAN,
        @as(u64, @bitCast(sdl.WindowFlags{ .vulkan = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_WINDOW_NOT_FOCUSABLE,
        @as(u64, @bitCast(sdl.WindowFlags{ .not_focusable = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_WINDOW_KEYBOARD_GRABBED,
        @as(u64, @bitCast(sdl.WindowFlags{ .keyboard_grabbed = true })),
    );
}

test "modifier bits match the C constants" {
    try std.testing.expectEqual(
        sdl.raw.SDL_KMOD_LSHIFT,
        @as(u16, @bitCast(sdl.KeyMod{ .left_shift = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_KMOD_RCTRL,
        @as(u16, @bitCast(sdl.KeyMod{ .right_ctrl = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_KMOD_CAPS,
        @as(u16, @bitCast(sdl.KeyMod{ .caps_lock = true })),
    );
    try std.testing.expectEqual(@as(u16, 0), @as(u16, @bitCast(sdl.KeyMod.none)));

    // The `ctrl`/`shift`/`alt` helpers are side-agnostic on purpose.
    const right_only: sdl.KeyMod = .{ .right_ctrl = true };
    try std.testing.expect(right_only.ctrl());
    try std.testing.expect(!right_only.shift());
}

test "mouse button state matches the C masks" {
    try std.testing.expectEqual(
        sdl.raw.SDL_BUTTON_LMASK,
        @as(u32, @bitCast(sdl.mouse.ButtonState{ .left = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_BUTTON_RMASK,
        @as(u32, @bitCast(sdl.mouse.ButtonState{ .right = true })),
    );

    const held: sdl.mouse.ButtonState = .{ .left = true, .x2 = true };
    try std.testing.expect(held.isDown(.left));
    try std.testing.expect(held.isDown(.x2));
    try std.testing.expect(!held.isDown(.middle));
}

test "enums match the C constants" {
    try std.testing.expectEqual(
        sdl.raw.SDL_SCANCODE_ESCAPE,
        @backingInt(sdl.Scancode.escape),
    );
    try std.testing.expectEqual(sdl.raw.SDL_SCANCODE_A, @backingInt(sdl.Scancode.a));
    try std.testing.expectEqual(sdl.raw.SDLK_RETURN, @backingInt(sdl.Keycode.@"return"));
    try std.testing.expectEqual(sdl.raw.SDL_BUTTON_LEFT, @backingInt(sdl.mouse.Button.left));
    try std.testing.expectEqual(sdl.raw.SDL_BLENDMODE_BLEND, @backingInt(sdl.BlendMode.blend));
    try std.testing.expectEqual(
        sdl.raw.SDL_PIXELFORMAT_RGBA8888,
        @backingInt(sdl.PixelFormat.rgba8888),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_GAMEPAD_BUTTON_SOUTH,
        @backingInt(sdl.gamepad.Button.south),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        @backingInt(sdl.gpu.TextureFormat.r8g8b8a8_unorm),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_GPU_SHADERFORMAT_SPIRV,
        @as(u32, @bitCast(sdl.gpu.ShaderFormat{ .spirv = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        @as(u32, @bitCast(sdl.gpu.TextureUsage{ .color_target = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_GPU_BUFFERUSAGE_INDEX,
        @as(u32, @bitCast(sdl.gpu.BufferUsage{ .index = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_GPU_COLORCOMPONENT_R | sdl.raw.SDL_GPU_COLORCOMPONENT_A,
        @as(u8, @bitCast(sdl.gpu.ColorComponent{ .r = true, .a = true })),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_MESSAGEBOX_WARNING,
        @as(u32, @bitCast(sdl.video.MessageBoxFlags.warning_box)),
    );
    try std.testing.expectEqual(
        sdl.raw.SDL_SURFACE_LOCK_NEEDED,
        @as(u32, @bitCast(sdl.surface.SurfaceFlags{ .lock_needed = true })),
    );
}

test "an unnamed scancode does not crash formatting" {
    // Scancode is non-exhaustive, so a value SDL sends that we did not name is
    // representable -- and `{t}` would panic on it. tagName returns null.
    const unnamed: sdl.Scancode = @fromBackingInt(@intCast(9999));
    try std.testing.expectEqualStrings(
        "unnamed",
        std.enums.tagName(sdl.Scancode, unnamed) orelse "unnamed",
    );
    try std.testing.expectEqualStrings(
        "escape",
        std.enums.tagName(sdl.Scancode, .escape).?,
    );
}

test "colours convert both ways" {
    const opaque_white: sdl.Color = .white;
    try std.testing.expectEqual(@as(u8, 255), opaque_white.a);

    const half = sdl.Color.rgba(255, 128, 0, 255).toFloat();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), half.r, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.502), half.g, 0.005);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), half.b, 0.001);
}

test "rect geometry" {
    const a: sdl.Rect = .{ .x = 0, .y = 0, .w = 10, .h = 10 };
    const b: sdl.Rect = .{ .x = 5, .y = 5, .w = 10, .h = 10 };
    const c: sdl.Rect = .{ .x = 100, .y = 100, .w = 1, .h = 1 };

    try std.testing.expect(a.intersects(b));
    try std.testing.expect(!a.intersects(c));

    const overlap = a.intersection(b).?;
    try std.testing.expectEqual(@as(i32, 5), overlap.x);
    try std.testing.expectEqual(@as(i32, 5), overlap.w);
    try std.testing.expect(a.intersection(c) == null);

    const merged = a.unionWith(b);
    try std.testing.expectEqual(@as(i32, 15), merged.w);

    try std.testing.expect((sdl.Point{ .x = 3, .y = 3 }).inRect(a));
    try std.testing.expect(!(sdl.Point{ .x = 30, .y = 3 }).inRect(a));
    try std.testing.expect((sdl.Rect{ .w = 0, .h = 5 }).isEmpty());
}

test "audio formats describe themselves" {
    try std.testing.expectEqual(@as(u8, 4), sdl.audio.Format.f32le.bytesPerSample());
    try std.testing.expectEqual(@as(u8, 2), sdl.audio.Format.s16le.bytesPerSample());
    try std.testing.expect(sdl.audio.Format.f32le.isFloat());
    try std.testing.expect(!sdl.audio.Format.s16le.isFloat());
    try std.testing.expect(sdl.audio.Format.s16le.isSigned());
    try std.testing.expect(!sdl.audio.Format.u8.isSigned());

    const spec: sdl.audio.Spec = .{ .format = sdl.audio.Format.f32le, .channels = 2 };
    try std.testing.expectEqual(@as(usize, 8), spec.frameSize());
}

test "pixel formats describe themselves" {
    const details = sdl.PixelFormat.rgba8888.details().?;
    try std.testing.expectEqual(@as(u8, 32), details.bits_per_pixel);
    try std.testing.expectEqual(@as(u8, 4), details.bytes_per_pixel);

    // Round-tripping through the format is the check that the mask and shift
    // fields landed in the right places.
    const original = sdl.Color.rgba(10, 20, 30, 40);
    const packed_pixel = details.map(original, null);
    try std.testing.expectEqual(original, details.unmap(packed_pixel, null));
}

test "an error carries SDL's description" {
    sdl.clearError();
    // A window cannot be made before the video subsystem exists, and even if
    // one could, a null title is not a thing SDL accepts.
    const missing = sdl.Window.fromId(0xFFFF_FFFF);
    try std.testing.expect(missing == null);
    try std.testing.expect(sdl.lastErrorText().len > 0);
}

// ---------------------------------------------------------------------
// Things that need a real subsystem
//
// SDL cannot start video in a headless environment, so these skip rather
// than fail there.
// ---------------------------------------------------------------------

test "surfaces hold pixels" {
    sdl.init(.{}) catch return error.SkipZigTest;
    defer sdl.quit();

    const image = try sdl.Surface.init(4, 4, .rgba32);
    defer image.deinit();

    try std.testing.expectEqual(@as(c_int, 4), image.w);
    try std.testing.expect(image.pitch >= 16);

    try image.writePixel(1, 1, .rgba(10, 20, 30, 255));
    const read_back = try image.readPixel(1, 1);
    try std.testing.expectEqual(@as(u8, 10), read_back.r);
    try std.testing.expectEqual(@as(u8, 30), read_back.b);

    const converted = try image.convert(.rgb24);
    defer converted.deinit();
    try std.testing.expectEqual(sdl.PixelFormat.rgb24, converted.format);

    const bigger = try image.scaled(8, 8, .nearest);
    defer bigger.deinit();
    try std.testing.expectEqual(@as(c_int, 8), bigger.w);
}

test "the software renderer draws without a window" {
    sdl.init(.{}) catch return error.SkipZigTest;
    defer sdl.quit();

    const target = try sdl.Surface.init(8, 8, .rgba32);
    defer target.deinit();

    const renderer = try sdl.Renderer.initSoftware(target);
    defer renderer.deinit();

    try renderer.setDrawColor(.rgb(255, 0, 0));
    try renderer.clear();
    try renderer.setDrawColor(.rgb(0, 0, 255));
    try renderer.fillRect(.{ .x = 0, .y = 0, .w = 4, .h = 4 });
    try renderer.present();

    try std.testing.expectEqual(sdl.Color.rgb(0, 0, 255), try target.readPixel(1, 1));
    try std.testing.expectEqual(sdl.Color.rgb(255, 0, 0), try target.readPixel(6, 6));
}

test "properties round-trip" {
    sdl.init(.{}) catch return error.SkipZigTest;
    defer sdl.quit();

    const props = try sdl.Properties.init();
    defer props.deinit();

    try props.setNumber("count", 42);
    try props.setString("name", "sdl3-zig");
    try props.setBool("ready", true);

    try std.testing.expectEqual(@as(i64, 42), props.getNumber("count", 0));
    try std.testing.expectEqualStrings("sdl3-zig", props.getString("name", ""));
    try std.testing.expect(props.getBool("ready", false));
    try std.testing.expect(!props.has("missing"));
    try std.testing.expectEqual(sdl.properties.PropertyType.number, props.typeOf("count"));

    // A missing key falls back rather than failing.
    try std.testing.expectEqual(@as(i64, -1), props.getNumber("missing", -1));
}

test "the timer clocks move forward" {
    sdl.init(.{}) catch return error.SkipZigTest;
    defer sdl.quit();

    const start = sdl.timer.performanceCounter();
    sdl.timer.delay(2);
    const elapsed = sdl.timer.secondsBetween(start, sdl.timer.performanceCounter());
    try std.testing.expect(elapsed > 0);
    try std.testing.expect(sdl.timer.performanceFrequency() > 0);
}

test "hints round-trip" {
    sdl.init(.{}) catch return error.SkipZigTest;
    defer sdl.quit();

    try sdl.hints.set(sdl.hints.names.render_driver, "software");
    try std.testing.expectEqualStrings("software", sdl.hints.get(sdl.hints.names.render_driver).?);
    try sdl.hints.reset(sdl.hints.names.render_driver);
}

test "a window reports what it was asked for" {
    sdl.init(.{ .video = true }) catch return error.SkipZigTest;
    defer sdl.quit();

    const window = sdl.Window.init("test", 320, 240, .{ .hidden = true }) catch
        return error.SkipZigTest;
    defer window.deinit();

    const size = try window.size();
    try std.testing.expectEqual(@as(i32, 320), size.width);
    try std.testing.expectEqual(@as(i32, 240), size.height);

    // A hidden window is hidden, and the flags say so.
    try std.testing.expect(window.flags().hidden);

    try window.setTitle("renamed");
    try std.testing.expectEqualStrings("renamed", window.title());

    // The id round-trips, which is what every event handler depends on.
    const found = sdl.Window.fromId(window.id()).?;
    try std.testing.expectEqual(window.handle, found.handle);

    const pixels = try window.sizeInPixels();
    try std.testing.expect(pixels.width >= size.width);
}

test "displays report modes" {
    sdl.init(.{ .video = true }) catch return error.SkipZigTest;
    defer sdl.quit();

    const display = sdl.Display.primary() catch return error.SkipZigTest;
    try std.testing.expect(display.name().len > 0);
    try std.testing.expect(display.contentScale() > 0);

    const mode = try display.desktopMode();
    try std.testing.expect(mode.w > 0 and mode.h > 0);

    var modes = try display.fullscreenModes();
    defer modes.deinit();
    try std.testing.expect(modes.count() > 0);
    try std.testing.expect(modes.next() != null);
}

test "the event queue takes what we push" {
    sdl.init(.{ .video = true }) catch return error.SkipZigTest;
    defer sdl.quit();

    const event_type = try sdl.events.registerEvents(1);
    try sdl.events.pushUser(event_type, 7, null, null);

    // Drain until our own event turns up; SDL will have queued some of its
    // own by now.
    var found = false;
    while (sdl.events.poll()) |event| {
        switch (event) {
            .user => |e| if (e.type == event_type) {
                try std.testing.expectEqual(@as(i32, 7), e.code);
                found = true;
            },
            else => {},
        }
    }
    try std.testing.expect(found);
}

test "textures round-trip through a renderer" {
    sdl.init(.{ .video = true }) catch return error.SkipZigTest;
    defer sdl.quit();

    const window = sdl.Window.init("texture", 64, 64, .{ .hidden = true }) catch
        return error.SkipZigTest;
    defer window.deinit();

    const renderer = sdl.Renderer.init(window, null) catch return error.SkipZigTest;
    defer renderer.deinit();

    const texture = try sdl.Texture.init(renderer, .rgba32, .streaming, 8, 8);
    defer texture.deinit();

    const size = try texture.size();
    try std.testing.expectEqual(@as(f32, 8), size.width);

    const locked = try texture.lock(null);
    try std.testing.expect(locked.pixels.len >= 8 * 8 * 4);
    @memset(locked.pixels, 0x40);
    texture.unlock();

    try renderer.setDrawColor(.black);
    try renderer.clear();
    try renderer.texture(texture, null, null);
    try renderer.present();
}
