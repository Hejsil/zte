const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const test_step = b.step("test", "Run tests");
    const tests = b.addTest("src/test.zig");
    tests.setBuildMode(mode);
    test_step.dependOn(&tests.step);

    const exe = b.addExecutable("zte", "src/main.zig");
    exe.setBuildMode(mode);
    exe.linkSystemLibrary("c");

    const fmt_step = b.addFmt([_][]const u8{
        "build.zig",
        "src",
    });

    b.default_step.dependOn(&fmt_step.step);
    b.default_step.dependOn(test_step);
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
