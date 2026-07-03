const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "nonosolver",
        .root_module = root,
    });

    if (target.result.os.tag == .windows) {
        exe.subsystem = .Windows;
    }

    const dvui_dep = b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 });
    exe.root_module.addImport("dvui", dvui_dep.module("dvui_sdl3"));

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "run exe");
    run_step.dependOn(&run.step);

    const test_exe = b.addTest(.{ .root_module = root });
    const test_run = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "run test");
    test_step.dependOn(&test_run.step);
}
