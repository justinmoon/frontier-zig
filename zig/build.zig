const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const cargo_profile = if (optimize == .Debug) "debug" else "release";
    const resolved_target = target.result;
    const target_os = resolved_target.os.tag;
    const target_triple = getCargoTargetTriple(b, resolved_target);

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

    const lib_basename = switch (target_os) {
        .windows => "frontier_blitz_bridge.dll",
        .macos => "libfrontier_blitz_bridge.dylib",
        else => "libfrontier_blitz_bridge.so",
    };

    const cargo_build = b.addSystemCommand(&[_][]const u8{
        "cargo",
        "rustc",
        "--manifest-path",
        "rust/Cargo.toml",
    });
    if (optimize != .Debug) cargo_build.addArg("--release");
    cargo_build.addArg("--target");
    cargo_build.addArg(target_triple);
    cargo_build.addArg("--");
    cargo_build.addArg("-C");
    if (target_os == .macos) {
        // Allow undefined symbols (Zig will provide them)
        cargo_build.addArg(b.fmt("link-arg=-Wl,-install_name,@rpath/{s},-undefined,dynamic_lookup", .{lib_basename}));
    } else {
        cargo_build.addArg("link-arg=-Wl,--allow-shlib-undefined");
    }

    const cargo_output_dir = b.pathJoin(&.{ "..", "rust", "target", target_triple, cargo_profile });
    const cargo_library_path = b.pathJoin(&.{ cargo_output_dir, lib_basename });

    const bridge_source = b.path(cargo_library_path);
    const install_rust_bridge = b.addInstallFileWithDir(
        bridge_source,
        .lib,
        lib_basename,
    );
    install_rust_bridge.step.dependOn(&cargo_build.step);
    deps_step.dependOn(&install_rust_bridge.step);

    if (target_os == .windows) {
        const install_bridge_bin = b.addInstallFileWithDir(
            bridge_source,
            .bin,
            lib_basename,
        );
        install_bridge_bin.step.dependOn(&cargo_build.step);
        deps_step.dependOn(&install_bridge_bin.step);
    }

    exe.addLibraryPath(b.path(cargo_output_dir));
    exe.linkSystemLibrary("frontier_blitz_bridge");
    exe.each_lib_rpath = false;
    if (target_os == .macos) {
        exe.root_module.addRPathSpecial("@executable_path/../lib");
    } else if (target_os == .linux) {
        exe.root_module.addRPathSpecial("$ORIGIN/../lib");
    }

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

    // Allow passing arguments to the run command
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the frontier-zig host executable.");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = root_module,
    });

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run frontier-zig unit tests.");
    test_step.dependOn(&run_tests.step);
}

fn getCargoTargetTriple(b: *std.Build, target: std.Target) []const u8 {
    const arch = @tagName(target.cpu.arch);
    return switch (target.os.tag) {
        .macos => b.fmt("{s}-apple-darwin", .{arch}),
        .linux => blk: {
            const abi_suffix = switch (target.abi) {
                .gnu => "gnu",
                .musl => "musl",
                .gnueabihf => "gnueabihf",
                .musleabihf => "musleabihf",
                else => @tagName(target.abi),
            };
            break :blk b.fmt("{s}-unknown-linux-{s}", .{ arch, abi_suffix });
        },
        .windows => blk: {
            const abi_suffix = switch (target.abi) {
                .gnu => "gnu",
                .msvc => "msvc",
                else => @tagName(target.abi),
            };
            break :blk b.fmt("{s}-pc-windows-{s}", .{ arch, abi_suffix });
        },
        else => @panic("unsupported cargo target"),
    };
}
