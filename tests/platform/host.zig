//! Test-only Roc host that writes the generated PDF to stdout and reports the
//! number of Roc allocation events to stderr.
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");

pub const std_options: std.Options = .{
    .allow_stack_tracing = false,
};

const HostEnv = struct {
    gpa: std.heap.DebugAllocator(.{}),
    roc_env: abi.RocEnv,
};

extern fn roc_main(args: abi.RocList(abi.RocStr)) callconv(.c) abi.RocListWith(u8, false);

var roc_host: ?*abi.RocHost = null;
var allocation_events: usize = 0;

comptime {
    if (!builtin.is_test) {
        @export(&main, .{ .name = "main" });
        @export(&hostAlloc, .{ .name = "roc_alloc", .visibility = .hidden });
        @export(&hostDealloc, .{ .name = "roc_dealloc", .visibility = .hidden });
        @export(&hostRealloc, .{ .name = "roc_realloc", .visibility = .hidden });
        @export(&hostDbg, .{ .name = "roc_dbg", .visibility = .hidden });
        @export(&hostExpectFailed, .{ .name = "roc_expect_failed", .visibility = .hidden });
        @export(&hostCrashed, .{ .name = "roc_crashed", .visibility = .hidden });
    }
}

fn main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    return platformMain(@intCast(argc), argv);
}

fn hostAlloc(length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    allocation_events += 1;
    return abi.DefaultAllocators.rocAlloc(roc_host.?, length, alignment);
}

fn hostDealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    abi.DefaultAllocators.rocDealloc(roc_host.?, ptr, alignment);
}

fn hostRealloc(ptr: *anyopaque, new_length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    allocation_events += 1;
    return abi.DefaultAllocators.rocRealloc(roc_host.?, ptr, new_length, alignment);
}

fn hostDbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocDbg(roc_host.?, bytes, len);
}

fn hostExpectFailed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocExpectFailed(roc_host.?, bytes, len);
}

fn hostCrashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocCrashed(roc_host.?, bytes, len);
}

fn platformMain(argc: usize, argv: [*][*:0]u8) c_int {
    const io = std.Io.Threaded.global_single_threaded.io();
    var host_env = HostEnv{
        .gpa = std.heap.DebugAllocator(.{}){},
        .roc_env = undefined,
    };
    host_env.roc_env = .{
        .allocator = host_env.gpa.allocator(),
        .roc_io = abi.RocIo.default(),
    };

    var host = abi.makeRocHost(&host_env.roc_env);
    roc_host = &host;

    const args = buildStrArgsList(argc, argv, &host);
    allocation_events = 0;

    var pdf = roc_main(args);
    std.Io.File.stdout().writeStreamingAll(io, pdf.items()) catch return 1;
    pdf.decref(&host);

    if (host_env.gpa.deinit() == .leak) {
        std.Io.File.stderr().writeStreamingAll(io, "ROC_HOST_LEAK\n") catch {};
        return 1;
    }

    var buffer: [64]u8 = undefined;
    const report = std.fmt.bufPrint(&buffer, "ROC_ALLOCATIONS={d}\n", .{allocation_events}) catch return 1;
    std.Io.File.stderr().writeStreamingAll(io, report) catch return 1;
    return 0;
}

fn buildStrArgsList(
    argc: usize,
    argv: [*][*:0]u8,
    host: *abi.RocHost,
) abi.RocList(abi.RocStr) {
    if (argc == 0) return abi.RocList(abi.RocStr).empty();

    const args = abi.RocList(abi.RocStr).allocate(argc, host);
    const values = args.elements_ptr.?;
    for (0..argc) |index| {
        const value = argv[index];
        const length = std.mem.len(value);
        values[index] = abi.RocStr.fromSlice(value[0..length], host);
    }
    return args;
}
