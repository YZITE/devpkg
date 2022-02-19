const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    //const lib = b.addStaticLibrary("yz-devpkg", "src/main.zig");
    //lib.setBuildMode(mode);
    //lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const mmzx = b.addExecutable("mmzx", "src/mmzx.zig");
    mmzx.setTarget(target);
    mmzx.setBuildMode(mode);
    mmzx.install();

    const mmzx_run_cmd = mmzx.run();
    mmzx_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        mmzx_run_cmd.addArgs(args);
    }

    const mmzx_run_step = b.step("run-mmzx", "Run mmzx");
    mmzx_run_step.dependOn(&mmzx_run_cmd.step);

    const all = b.step("all", "Build all executables");
    all.dependOn(test_step);
    all.dependOn(&mmzx.step);
    all.dependOn(b.getInstallStep());
}
