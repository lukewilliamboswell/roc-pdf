const std = @import("std");

const RocTarget = enum {
    arm64mac,
    x64musl,

    fn query(self: RocTarget) std.Target.Query {
        return switch (self) {
            .arm64mac => .{ .cpu_arch = .aarch64, .os_tag = .macos },
            .x64musl => .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        };
    }

    fn directory(self: RocTarget) []const u8 {
        return switch (self) {
            .arm64mac => "arm64mac",
            .x64musl => "x64musl",
        };
    }
};

const targets = [_]RocTarget{ .arm64mac, .x64musl };

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const copy_hosts = b.addUpdateSourceFiles();

    for (targets) |roc_target| {
        const host = b.addLibrary(.{
            .name = "host",
            .linkage = .static,
            .root_module = b.createModule(.{
                .root_source_file = b.path("host.zig"),
                .target = b.resolveTargetQuery(roc_target.query()),
                .optimize = optimize,
                .strip = optimize != .Debug,
                .pic = true,
            }),
        });
        host.bundle_compiler_rt = true;

        copy_hosts.addCopyFileToSource(
            host.getEmittedBin(),
            b.pathJoin(&.{ "targets", roc_target.directory(), "libhost.a" }),
        );

        const retention_host = b.addLibrary(.{
            .name = "retention_host",
            .linkage = .static,
            .root_module = b.createModule(.{
                .root_source_file = b.path("retention_host.zig"),
                .target = b.resolveTargetQuery(roc_target.query()),
                .optimize = optimize,
                .strip = optimize != .Debug,
                .pic = true,
            }),
        });
        retention_host.bundle_compiler_rt = true;

        copy_hosts.addCopyFileToSource(
            retention_host.getEmittedBin(),
            b.pathJoin(&.{ "../retention_platform/targets", roc_target.directory(), "libretention_host.a" }),
        );

        if (roc_target == .x64musl) {
            const startup = muslStaticPieStartup(b, b.resolveTargetQuery(roc_target.query()));
            copy_hosts.addCopyFileToSource(startup, "targets/x64musl/rcrt1.o");
            copy_hosts.addCopyFileToSource(startup, "../retention_platform/targets/x64musl/rcrt1.o");
            copy_hosts.addCopyFileToSource(
                b.path("targets/x64musl/libc.a"),
                "../retention_platform/targets/x64musl/libc.a",
            );
        }
    }

    b.getInstallStep().dependOn(&copy_hosts.step);
}

// Roc's static PIE executables need musl's self-relocating startup. Compile
// the pinned Zig distribution's musl sources instead of retaining a second
// architecture-specific startup binary.
fn muslStaticPieStartup(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.LazyPath {
    const obj = b.addObject(.{
        .name = "rcrt1_x86_64",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .ReleaseSmall,
            .pic = true,
            .link_libc = true,
            .stack_protector = false,
        }),
    });
    obj.root_module.addCSourceFile(.{
        .file = zigLibPath(b, "libc/musl/crt/rcrt1.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE", "-ffreestanding", "-fno-builtin", "-fvisibility=hidden" },
    });
    for ([_][]const u8{
        "libc/musl/arch/x86_64",
        "libc/musl/arch/generic",
        "libc/musl/src/internal",
        "libc/musl/src/include",
    }) |path| obj.root_module.addIncludePath(zigLibPath(b, path));
    return obj.getEmittedBin();
}

fn zigLibPath(b: *std.Build, sub_path: []const u8) std.Build.LazyPath {
    return .{ .cwd_relative = b.graph.zig_lib_directory.join(b.allocator, &.{sub_path}) catch @panic("OOM") };
}
