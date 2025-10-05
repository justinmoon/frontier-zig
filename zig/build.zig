const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
    });
    root_module.resolved_target = target;
    root_module.optimize = optimize;

    const exe = b.addExecutable(.{
        .name = "frontier-zig",
        .root_module = root_module,
    });

    const deps_step = b.step("deps", "Build supporting artifacts (Rust bridge, Bun assets).");

    const rust_placeholder = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        "echo '[phase0] TODO: compile Rust Blitz bridge (skipped)'",
    });
    deps_step.dependOn(&rust_placeholder.step);

    const bun_placeholder = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        "echo '[phase0] TODO: bundle Bun assets (skipped)'",
    });
    deps_step.dependOn(&bun_placeholder.step);

    exe.step.dependOn(deps_step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the frontier-zig host executable.");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = root_module,
    });

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run frontier-zig unit tests.");
    test_step.dependOn(&run_tests.step);
}
