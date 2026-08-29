---
name: sdl3-zig
description: Integrate, configure, test, and debug the sdl3-zig Zig 0.17 bindings for SDL 3. Use when an agent needs SDL windows, events, input, the 2D renderer, audio, or the SDL GPU API from Zig; needs a Vulkan surface or the required instance extensions; needs to combine SDL with vk-zig or imgui-zig; or must reach parts of the SDL API the wrapper does not yet cover.
---

# SDL 3 in Zig

Use the idiomatic `sdl3` module by default. Reach for `sdl.raw` only when the wrapper does not yet
cover an SDL call.

## Add the dependency

```sh
zig fetch --save=sdl3 git+https://github.com/zmscode/sdl3-zig.git
```

```zig
const dependency = b.dependency("sdl3", .{
    .target = target,
    .optimize = optimize,
    .vulkan = true,   // only if you need surface creation
});

exe.root_module.addImport("sdl3", dependency.module("sdl3"));
```

SDL 3.4.14 is compiled from pinned source as part of the build. There is no system SDL to install.

## The shape of a program

```zig
const sdl = @import("sdl3");

try sdl.init(.{ .video = true });
defer sdl.quit();

const both = try sdl.createWindowAndRenderer("app", 960, 540, .{ .resizable = true });
defer both.renderer.deinit();
defer both.window.deinit();

try both.renderer.setVSync(1);

main: while (true) {
    while (sdl.events.poll()) |event| switch (event) {
        .quit => break :main,
        .window => |e| if (e.kind == .close_requested) break :main,
        else => {},
    };
    try both.renderer.setDrawColor(.rgb(20, 22, 30));
    try both.renderer.clear();
    try both.renderer.present();
}
```

## Six things to get right

1. **Handles are values, not pointers to wrap.** `Window`, `Renderer`, `Texture`, `Gamepad` are
   one-pointer structs passed by value. `Surface` is the exception: it is SDL's own struct, so it
   is used as `*Surface`, and so are all the `gpu` handles.
2. **Screen coordinates are not pixels.** `window.size()` is in screen coordinates;
   `window.sizeInPixels()` is in pixels. On a Retina display they differ by 2x, and only if the
   window was created with `.high_pixel_density = true`. Anything you pass to a viewport, a
   swapchain or a framebuffer wants the pixel size. The event to react to is
   `.window => .pixel_size_changed`, not `.resized`.
3. **Printing an input enum can panic.** `Scancode`, `Keycode`, `mouse.Button`,
   `gamepad.Button`, `PixelFormat` and the rest are non-exhaustive, so a value SDL sends that the
   enum does not name is representable — and `{t}` panics on it. Use
   `std.enums.tagName(sdl.Scancode, code) orelse "unnamed"`.
4. **Scancode vs keycode.** A `Scancode` is a physical key position; a `Keycode` is what that key
   types under the current layout. Bind movement to scancodes and shortcuts to keycodes, and
   neither breaks on an AZERTY keyboard.
5. **There is one error.** SDL has no error codes: every failure is `error.SdlError`, and the
   detail is in `sdl.lastErrorText()`, which is thread-local and overwritten by the next failure.
   Read it immediately, and `sdl.clearError()` before a sequence you intend to inspect.
6. **Some strings are borrowed and some are owned.** A `[]const u8` returned by a getter is SDL's,
   valid until the next call that changes it. The few that are SDL-allocated say so and have a
   matching free: `clipboardText` / `freeClipboardText`, `prefPath` / `freePath`, `loadFile` /
   `freeFile`, `Display.all` / `freeDisplays`, `Wav.load` / `deinit`.

## Events

`Event` is a `union(enum)`, so the payload you can reach is the payload the tag says is there:

```zig
while (sdl.events.poll()) |event| switch (event) {
    .quit => break :main,
    .window => |e| switch (e.kind) {
        .close_requested => break :main,
        .pixel_size_changed => |size| resize(size.width, size.height),
        else => {},
    },
    .key_down => |e| if (e.key == .q and e.mod.ctrl()) break :main,
    .mouse_motion => |e| look(e.xrel, e.yrel),   // not a difference of e.x
    .text_input => |e| append(e.text),           // borrowed until the next poll
    .other => |raw_event| {},                    // anything not yet named
    else => {},
};
```

- SDL's 24 window event types fold into one `.window` variant with a `kind` union.
- `poll` pumps the queue, so a polling loop needs no separate `sdl.events.pump()`. A loop that
  reads `keyboard.state()` _without_ draining the queue does need it.
- `waitTimeout(ms)` blocks without spinning; `wait()` blocks indefinitely.
- `event.isQuitFor(window.id())` covers the two events that end an application.
- Text pointers in `.text_input`, `.text_editing` and `.drop_*` are borrowed until the next poll.
  Copy them to keep them.
- User events need `sdl.events.registerEvents(n)` first, then `pushUser`.

## Input

```zig
const keys = sdl.keyboard.state();          // fetch after pumping, read every frame
if (keys.isDown(.space)) jump();

const mouse = sdl.mouse.state();
if (mouse.buttons.isDown(.left)) fire();

try window.setRelativeMouseMode(true);      // hides the cursor, unbounded deltas
```

Gamepads arrive as events, not by polling for devices:

```zig
.gamepad_added => |e| pad = try sdl.Gamepad.init(e.which),
.gamepad_removed => |e| if (pad) |p| { p.deinit(); pad = null; },
```

`gamepad.Button` names positions (`.south`), not labels. `pad.buttonLabel(.south)` gives the label
to print — Cross on a PlayStation pad, A on an Xbox one. `pad.axisFloat(.left_x)` normalises to
-1..1; SDL applies no dead zone, so apply your own.

## The 2D renderer

```zig
try renderer.setLogicalPresentation(320, 180, .integer_scale);  // fixed resolution, scaled to fit
try renderer.setDrawBlendMode(.blend);
try renderer.fillRect(.{ .x = 20, .y = 30, .w = 80, .h = 50 });
try renderer.texture(tex, null, dst);                            // null src = whole texture
try renderer.debugText(8, 8, "no font file needed");
```

- Draws are batched until `present()`, so a frame costs one flush.
- With a logical presentation set, mouse coordinates need
  `renderer.coordinatesFromWindow(x, y)` before they mean anything.
- `Texture.lock` returns write-only staging memory whose contents are undefined; write it whole.
- `Renderer.initSoftware(surface)` needs no window at all, which makes it the renderer that works
  headless — useful in tests.

## The GPU API

```zig
const device = try sdl.gpu.Device.init(.{ .spirv = true, .msl = true }, true, null);
defer device.deinit();
try device.claimWindow(window);
defer device.releaseWindow(window);

const cmd = try device.acquireCommandBuffer();
const swapchain = try cmd.waitAndAcquireSwapchainTexture(window);
if (swapchain.texture) |target| {
    const pass = try cmd.beginRenderPass(&.{.{
        .texture = target,
        .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.12, .a = 1 },
        .load_op = .clear,
        .store_op = .store,
    }}, null);
    pass.bindGraphicsPipeline(pipeline);
    pass.drawPrimitives(3, 1, 0, 0);
    pass.end();
}
try cmd.submit();
```

- `swapchain.texture` null is **not** an error: the window is minimised, or every frame slot is in
  flight. Skip the drawing and submit the command buffer anyway.
- A swapchain texture is owned by the swapchain. Never release it, and never touch it after
  `submit()`.
- A command buffer belongs to the thread that acquired it.
- Resources are released with `device.release*`, and the release is deferred until the GPU is
  done — so it is safe while work is in flight, but not while an unsubmitted command buffer still
  references the resource. `device.waitForIdle()` before teardown is the blunt way to be sure.
- Shaders are backend-specific bytecode. `device.shaderFormats()` says which format was taken;
  there is no cross-compilation here.
- Uniforms are _pushed_ onto the command buffer, not bound:
  `cmd.pushVertexUniform(0, matrices)`.
- `cycle = true` on a target or an upload asks for a fresh copy instead of waiting for the last
  use to finish. It is the GPU API's answer to double buffering.

## Audio

```zig
const stream = try sdl.audio.Stream.openDevice(.default_playback, .{
    .format = sdl.audio.Format.f32_native,
    .channels = 2,
    .freq = 48_000,
}, null, null);
defer stream.deinit();

try stream.put(std.mem.sliceAsBytes(samples));
try stream.play();                       // a device opened this way starts paused
```

- The spec is _yours_, not the device's: SDL resamples. `stream.device().format()` reports what the
  hardware actually runs at.
- Watch `stream.queued()` to keep the queue from running dry or growing forever.
- A callback set with `openDevice` or `setGetCallback` runs on SDL's audio thread.
- `Wav.load` allocates through SDL; free it with `wav.deinit()`.

## Vulkan

```zig
const window = try sdl.Window.init("app", 1280, 720, .{ .vulkan = true });

try sdl.vulkan.appendRequiredInstanceExtensions(&extension_set);   // vk-zig's ExtensionSet
const surface = try sdl.vulkan.createSurface(instance, window, null);
defer sdl.vulkan.destroySurface(instance, surface, null);
```

- Build with `-Dvulkan`, and create the window with `.vulkan = true`.
- Destroy the surface **before** the instance.
- SDL loads Vulkan itself and never links it, so it composes with vk-zig's dynamic loader;
  `sdl.vulkan.getInstanceProcAddr()` is the entry point to bootstrap from.
- Check `presentationSupport(instance, physical_device, queue_family)` before choosing a graphics
  queue, not after.

### Composing with vk-zig and imgui-zig

- **vk-zig** owns the instance, device and swapchain. sdl3-zig supplies the surface and the
  required instance extensions.
- **imgui-zig** takes native handles: pass `window.handle`, not `window`.
- Prefer SDL's own GPU API over Vulkan when you do not need Vulkan specifically — it is one
  backend-agnostic path instead of three.

## Build options

| Option     | Default | Effect                        |
| ---------- | ------- | ----------------------------- |
| `-Dvulkan` | `false` | Vulkan surface helpers        |
| `-Dshared` | `false` | Build SDL as a shared library |

## Validate a change

```sh
zig build test              # flag-bit and enum checks against the C constants
zig build test -Dvulkan     # the Vulkan module is comptime-gated; this checks it
zig build run-info          # drivers and displays; opens no window
zig build run-window -- --frames 60
zig build bindings          # inspect the translated C API in zig-out/bindings/sdl3.zig
```

Tests that need a display call `sdl.init(...) catch return error.SkipZigTest`, so the suite passes
in a headless environment rather than failing for the wrong reason. If you add a test that opens a
window, follow that pattern.

## Adding a wrapper

1. Find the call in `zig-out/bindings/sdl3.zig` after `zig build bindings`.
2. Put it on the handle type it takes, and at module scope otherwise. Group it in the `src/` file
   that matches SDL's own header.
3. Convert at the boundary: out-params become return structs, `ptr, count` pairs become slices,
   loose integer constants become an enum with a trailing `_`, and a bitmask becomes a `packed
struct` with an explicit backing integer.
4. If it can fail, `try check(...)` or `try errors.checkPtr(...)` rather than surfacing the bool.
5. Add a test. For a flag type, assert the bits against the C constants; for a struct handed to
   SDL by pointer, add a `comptime` size assertion against SDL's own.
