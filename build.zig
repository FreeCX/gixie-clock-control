const std = @import("std");

pub fn build(b: *std.Build) void {
    // default app
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "gixie",
        .root_module = exe_mod,
    });
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // special arm app
    const arm_exe = b.addExecutable(.{
        .name = "control",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/control.zig"),
            .target = b.resolveTargetQuery(std.Target.Query {
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabihf
            }),
            .optimize = .ReleaseSmall,
            .strip = true,
        }),
    });
    arm_exe.linkLibC();
    b.installArtifact(arm_exe);

    const build_arm = b.step("arm", "Build arm app");
    build_arm.dependOn(b.getInstallStep());
}
