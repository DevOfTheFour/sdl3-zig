const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan = b.option(bool, "vulkan", "Expose SDL's Vulkan surface helpers") orelse false;
    const shared = b.option(bool, "shared", "Build SDL as a shared library") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "vulkan", vulkan);

    // ---------------------------------------------------------------
    // SDL itself, compiled from pinned source. Nothing to install, and
    // it cross-compiles with the rest of the project.
    // ---------------------------------------------------------------
    const upstream = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .preferred_linkage = if (shared) std.builtin.LinkMode.dynamic else .static,
    });
    const sdl_lib = upstream.artifact("SDL3");

    // ---------------------------------------------------------------
    // The raw layer.
    // ---------------------------------------------------------------
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("vendor/sdl3_translate.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(upstream.path("include"));
    if (vulkan) translate_c.defineCMacro("SDL3_ZIG_VULKAN", "1");

    // ---------------------------------------------------------------
    // The idiomatic layer.
    // ---------------------------------------------------------------
    const sdl3 = b.addModule("sdl3", .{
        .root_source_file = b.path("src/sdl3.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sdl3_raw", .module = translate_c.createModule() },
            .{ .name = "sdl3_build_options", .module = options.createModule() },
        },
    });
    sdl3.linkLibrary(sdl_lib);

    b.installArtifact(sdl_lib);

    // ---------------------------------------------------------------
    // Steps
    // ---------------------------------------------------------------
    const bindings_step = b.step("bindings", "Write the translated C bindings to zig-out/bindings");
    bindings_step.dependOn(&b.addInstallFile(translate_c.getOutput(), "bindings/sdl3.zig").step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/smoke.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "sdl3", .module = sdl3 }},
    });
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the binding tests").dependOn(&run_tests.step);

    // Examples are built explicitly with `zig build examples`.
    // Keep them separate from the default install step.
    const examples_step = b.step("examples", "Build every example");

    for ([_][]const u8{
        "info",
        "window",
        "events",
        "shapes",
        "audio",
    }) |name| {
        addExample(b, examples_step, sdl3, target, optimize, name);
    }

    b.getInstallStep().dependOn(examples_step);
}

fn addExample(
    b: *std.Build,
    step: *std.Build.Step,
    sdl3: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "sdl3", .module = sdl3 }},
        }),
    });
    step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step(
        b.fmt("run-{s}", .{name}),
        b.fmt("Run the {s} example", .{name}),
    ).dependOn(&run.step);
}
