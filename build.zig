const std = @import("std");

pub fn build(b: *std.Build) void {
    const build_arm_app = b.option(bool, "arm", "build special arm app") orelse false;

    if (build_arm_app) {
        const arm_exe = b.addExecutable(.{
            .name = "control",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/control.zig"),
                .target = b.resolveTargetQuery(std.Target.Query {
                    .cpu_arch = .arm,
                    .os_tag = .linux,
                    .abi = .musleabihf
                }),
                .optimize = b.standardOptimizeOption(.{}),
                .strip = true,
            }),
        });
        b.installArtifact(arm_exe);
        return;
    }

    // default app step
    const exe = b.addExecutable(.{
        .name = "gixie",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
