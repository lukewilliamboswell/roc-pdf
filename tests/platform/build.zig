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
    }

    b.getInstallStep().dependOn(&copy_hosts.step);
}
