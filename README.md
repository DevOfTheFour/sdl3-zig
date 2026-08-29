# sdl3-zig

Zig 0.17 bindings for [SDL 3](https://github.com/libsdl-org/SDL). The package:

- builds SDL 3.4.14 from pinned source, so there is nothing to install and it cross-compiles;
- provides an idiomatic, resource-safe Zig API and the complete raw C ABI;
- covers video, the 2D renderer, events, keyboard, mouse, gamepads, audio, the GPU API,
  surfaces, properties, hints, logging, timers, and filesystem paths;
- optionally exposes SDL's Vulkan surface helpers, which compose with
  [vk-zig](https://github.com/zmscode/vk-zig)'s dynamic loader.

AI coding agents can use the repository's installable [`sdl3-zig` skill](SKILL.md) for concise,
version-specific integration guidance.

## Use as a dependency

```sh
zig fetch --save=sdl3 git+https://github.com/zmscode/sdl3-zig.git
```

For local development the equivalent path dependency is:

```zig
.dependencies = .{
    .sdl3 = .{ .path = "../sdl3-zig" },
},
```

Then expose the module to your executable in `build.zig`:

```zig
const sdl3_dependency = b.dependency("sdl3", .{
    .target = target,
    .optimize = optimize,
    .vulkan = true,   // optional: SDL's Vulkan surface helpers
});

exe.root_module.addImport("sdl3", sdl3_dependency.module("sdl3"));
```

Nothing else is needed — SDL itself is compiled as part of the build.

## A window

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
        .key_down => |e| if (e.key == .escape) break :main,
        else => {},
    };

    try both.renderer.setDrawColor(.rgb(20, 22, 30));
    try both.renderer.clear();
    try both.renderer.present();
}
```

`Window`, `Renderer` and `Texture` are one-pointer handles, copied freely and passed by value.
Nothing needs an allocator, because SDL owns its own memory — the allocator-taking calls in this
package are the ones that hand a Zig allocator's memory _to_ SDL, and there are none in the core
loop.

## What the wrapper changes

| SDL 3                                          | sdl3-zig                                                |
| ---------------------------------------------- | ------------------------------------------------------- |
| `SDL_CreateWindow` / `SDL_DestroyWindow`       | `Window.init` / `deinit`, with `defer`                  |
| `false` or `NULL` plus `SDL_GetError`          | an `Error` set; `lastErrorText` for the detail          |
| `SDL_Event` union plus a separate `type` tag   | `Event`, a `union(enum)` — the tag _is_ the payload     |
| 24 window event types                          | one `.window` variant with a `kind` union               |
| `SDL_WINDOW_*`, `SDL_INIT_*` as or-ed integers | `packed struct` with named bits                         |
| `SDL_SCANCODE_*`, `SDL_GAMEPAD_BUTTON_*`       | `Scancode`, `Keycode`, `gamepad.Button` enums           |
| `SDL_GetWindowSize(w, &x, &y)`                 | `try window.size()` returning a `Size`                  |
| `ptr, count` argument pairs                    | slices                                                  |
| `const char *`                                 | slices, with `[:0]const u8` where SDL keeps the pointer |

Anything not yet wrapped is reachable through `sdl.raw`, the complete translated SDL API.

## Events

SDL hands over a C union and a tag, and leaves the two to be kept in agreement by hand. Here they
are one thing:

```zig
while (sdl.events.poll()) |event| switch (event) {
    .quit => break :main,

    .window => |e| switch (e.kind) {
        .close_requested => break :main,
        // The *pixel* size, not the screen-coordinate size, is what a
        // renderer or swapchain has to react to.
        .pixel_size_changed => |size| resize(size.width, size.height),
        else => {},
    },

    .key_down => |e| {
        // Scancodes are physical positions; keycodes are what the layout types.
        if (e.scancode == .w) moveForward();
        if (e.key == .q and e.mod.ctrl()) break :main;
    },

    .mouse_button_down => |e| click(e.x, e.y, e.button),
    .gamepad_button_down => |e| if (e.button == .south) jump(),

    // Anything not yet named, with SDL's own union intact.
    .other => |raw_event| handle(raw_event),

    else => {},
};
```

> **Printing a key needs care.** `Scancode`, `Keycode` and the other input enums are
> non-exhaustive, so a value SDL sends that the enum does not name is representable — and `{t}`
> **panics** on exactly that value. Use `std.enums.tagName(sdl.Scancode, code) orelse "unnamed"`.

## The 2D renderer

```zig
const image = try sdl.Surface.loadBmp("sprite.bmp");
defer image.deinit();                       // the texture keeps its own copy

const texture = try sdl.Texture.initFromSurface(renderer, image);
defer texture.deinit();

// Draw at a fixed resolution and let SDL fit it to the window.
try renderer.setLogicalPresentation(320, 180, .integer_scale);

try renderer.setDrawBlendMode(.blend);
try renderer.setDrawColor(.rgba(90, 160, 250, 180));
try renderer.fillRect(.{ .x = 20, .y = 30, .w = 80, .h = 50 });
try renderer.textureRotated(texture, null, dst, angle, null, .none);
try renderer.debugText(8, 8, "no font file needed");
```

## The GPU API

SDL 3's explicit graphics and compute layer, over Vulkan, Metal and D3D12:

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

The GPU handles are `opaque` types used through pointers, not structs wrapping a pointer like
`Window` is. That is deliberate: the create-info structs hold `?*Texture` and `?*Buffer` fields
that SDL reads as plain C pointers, and only a real pointer type is guaranteed to survive being
made optional without growing a tag byte. Every one of those 35 structs has a `comptime` size and
alignment assertion against SDL's own.

Shaders are backend-specific bytecode — SPIR-V, DXIL, MSL — and there is no cross-compilation
here. `device.shaderFormats()` reports which format the device took.

## Audio

```zig
const stream = try sdl.audio.Stream.openDevice(.default_playback, .{
    .format = sdl.audio.Format.f32_native,
    .channels = 1,
    .freq = 48_000,
}, null, null);
defer stream.deinit();

try stream.put(std.mem.sliceAsBytes(samples));
try stream.play();
```

SDL 3 puts a resampling stream between you and the device, so the format you feed in has nothing
to do with the format the hardware wants. A callback set on a stream runs on SDL's audio thread.

## Vulkan

Build with `-Dvulkan`. SDL loads Vulkan itself and never links it, so this composes with a dynamic
loader such as [vk-zig](https://github.com/zmscode/vk-zig)'s rather than competing with it.

```zig
const window = try sdl.Window.init("app", 1280, 720, .{ .vulkan = true });

try sdl.vulkan.appendRequiredInstanceExtensions(&extension_set);
const surface = try sdl.vulkan.createSurface(instance, window, null);
defer sdl.vulkan.destroySurface(instance, surface, null);
```

## Examples

```sh
zig build run-info                  # drivers, displays, audio devices; opens no window
zig build run-window                # a window, its pixel size, its content scale
zig build run-events                # every event, printed as it arrives
zig build run-shapes                # rectangles, textures, geometry, logical presentation
zig build run-audio                 # a generated tone, or a WAV you name
zig build run-window -- --frames 60 # exit after N frames
```

## Build options

| Option     | Default | Effect                              |
| ---------- | ------- | ----------------------------------- |
| `-Dvulkan` | `false` | Expose SDL's Vulkan surface helpers |
| `-Dshared` | `false` | Build SDL as a shared library       |

macOS, Windows and Linux need nothing beyond the system SDK. A Linux build wants the usual X11 and
Wayland development packages; SDL selects backends at runtime, so a build that finds neither still
compiles and fails at `init`.

## Steps

```sh
zig build            # build SDL and the examples
zig build test       # run the binding tests
zig build examples   # build every example
zig build bindings   # write the translated C bindings to zig-out/bindings
```

## Layout

| Path                                                                                                      | What it is                                                                |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `src/sdl3.zig`                                                                                            | The root module: init, version, clipboard, and the re-exports             |
| `src/events.zig`                                                                                          | The `Event` tagged union and the queue                                    |
| `src/video.zig`, `src/render.zig`                                                                         | Windows, displays, the 2D renderer, textures                              |
| `src/gpu.zig`                                                                                             | The GPU API: devices, pipelines, passes, transfers                        |
| `src/audio.zig`, `src/keyboard.zig`, `src/mouse.zig`, `src/gamepad.zig`                                   | Devices and input                                                         |
| `src/pixels.zig`, `src/surface.zig`, `src/rect.zig`                                                       | Formats, colours, CPU images, geometry                                    |
| `src/io.zig`, `src/filesystem.zig`, `src/properties.zig`, `src/hints.zig`, `src/log.zig`, `src/timer.zig` | The rest                                                                  |
| `vendor/sdl3_translate.h`                                                                                 | Umbrella header; the single place compile-time options are set            |
| `examples/`                                                                                               | info, window, events, shapes, audio                                       |
| `tests/smoke.zig`                                                                                         | Binding tests, including flag-bit and enum checks against the C constants |

Tests that need a display skip rather than fail in a headless environment.

## Where SDL comes from

SDL is built by [castholm/SDL](https://github.com/castholm/SDL), which is upstream SDL ported to
the Zig build system, pinned here at `v0.5.3+3.4.14`. That is the same arrangement as building the
C sources directly — nothing to install, and it cross-compiles — without this package carrying its
own copy of SDL's several-hundred-file build configuration.
