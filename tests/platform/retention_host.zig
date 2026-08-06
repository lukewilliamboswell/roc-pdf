//! Test-only Roc host that verifies unchanged-resource backing allocations.
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");

pub const std_options: std.Options = .{
    .allow_stack_tracing = false,
};

const ByteList = abi.RocListWith(u8, false);

const HostEnv = struct {
    gpa: std.heap.DebugAllocator(.{}),
    roc_env: abi.RocEnv,
};

const RetentionResult = extern struct {
    backing: ByteList,
    bytes: ByteList,
    owned: ByteList,
    shared: ByteList,
    source: ByteList,
    work: abi.RocListWith(u64, false),
};

const RetentionFacts = struct {
    backing_refs: isize,
    owned_capacity: usize,
    source_offset: usize,
};

extern fn roc_main(args: abi.RocList(abi.RocStr)) callconv(.c) RetentionResult;

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
    const result = roc_main(args);

    const facts = inspectRetention(result) catch |err| {
        reportRetentionFailure(io, err) catch {};
        decrefResult(result, &host);
        _ = host_env.gpa.deinit();
        return switch (err) {
            error.BackingRefcount => 10,
            error.BackingShape => 11,
            error.ByteMismatch => 12,
            error.OwnedAllocation => 13,
            error.SharedAllocation => 14,
            error.SliceShape => 15,
        };
    };

    std.Io.File.stdout().writeStreamingAll(io, result.bytes.items()) catch return 1;
    reportRetention(io, facts) catch return 1;
    reportMetrics(io, result.work.items()) catch return 1;
    decrefResult(result, &host);

    if (host_env.gpa.deinit() == .leak) {
        std.Io.File.stderr().writeStreamingAll(io, "ROC_HOST_LEAK\n") catch {};
        return 1;
    }

    return 0;
}

const RetentionError = error{
    BackingRefcount,
    BackingShape,
    ByteMismatch,
    OwnedAllocation,
    SharedAllocation,
    SliceShape,
};

fn inspectRetention(result: RetentionResult) RetentionError!RetentionFacts {
    if (result.backing.len() != 8192 or result.backing.isSeamlessSlice()) {
        return error.BackingShape;
    }
    if (result.source.len() != 64 or result.shared.len() != 64 or result.owned.len() != 64) {
        return error.SliceShape;
    }
    if (!result.source.isSeamlessSlice() or !result.shared.isSeamlessSlice()) {
        return error.SliceShape;
    }
    if (result.owned.isSeamlessSlice()) return error.OwnedAllocation;

    const backing_alloc = allocationAddress(result.backing);
    const source_alloc = allocationAddress(result.source);
    const shared_alloc = allocationAddress(result.shared);
    const owned_alloc = allocationAddress(result.owned);
    if (backing_alloc == 0 or source_alloc != backing_alloc or shared_alloc != backing_alloc) {
        return error.SharedAllocation;
    }
    if (owned_alloc == 0 or owned_alloc == backing_alloc) return error.OwnedAllocation;

    const source_ptr = @intFromPtr(result.source.elements_ptr orelse return error.SliceShape);
    const shared_ptr = @intFromPtr(result.shared.elements_ptr orelse return error.SliceShape);
    if (source_ptr != shared_ptr or source_ptr < backing_alloc) return error.SharedAllocation;
    const source_offset = source_ptr - backing_alloc;
    if (source_offset != 4096) return error.SliceShape;

    if (!std.mem.eql(u8, result.source.items(), result.shared.items()) or
        !std.mem.eql(u8, result.source.items(), result.owned.items()))
    {
        return error.ByteMismatch;
    }

    const owned_capacity = result.owned.capacity_or_alloc_ptr >> 1;
    if (owned_capacity < result.owned.len() or owned_capacity > 64) {
        return error.OwnedAllocation;
    }

    const backing_refs = allocationRefcount(backing_alloc);
    if (backing_refs != 3) return error.BackingRefcount;

    return .{
        .backing_refs = backing_refs,
        .owned_capacity = owned_capacity,
        .source_offset = source_offset,
    };
}

fn allocationAddress(list: ByteList) usize {
    if (list.isEmpty()) return 0;
    if (list.isSeamlessSlice()) return list.capacity_or_alloc_ptr & ~@as(usize, 1);
    return @intFromPtr(list.elements_ptr orelse return 0);
}

fn allocationRefcount(allocation: usize) isize {
    const ptr: *const isize = @ptrFromInt(allocation - @sizeOf(isize));
    return ptr.*;
}

fn reportRetention(io: std.Io, facts: RetentionFacts) !void {
    const stderr = std.Io.File.stderr();
    var buffer: [160]u8 = undefined;
    const line = try std.fmt.bufPrint(
        &buffer,
        "ROC_RETENTION protocol=1 backing_refs={d} source_offset={d} owned_capacity={d}\n",
        .{ facts.backing_refs, facts.source_offset, facts.owned_capacity },
    );
    try stderr.writeStreamingAll(io, line);
}

fn reportRetentionFailure(io: std.Io, err: RetentionError) !void {
    const stderr = std.Io.File.stderr();
    try stderr.writeStreamingAll(io, "ROC_RETENTION_FAILURE ");
    try stderr.writeStreamingAll(io, @errorName(err));
    try stderr.writeStreamingAll(io, "\n");
}

fn reportMetrics(io: std.Io, work: []const u64) !void {
    const stderr = std.Io.File.stderr();
    var buffer: [64]u8 = undefined;
    const allocations = try std.fmt.bufPrint(&buffer, "{d}", .{allocation_events});
    try stderr.writeStreamingAll(io, "ROC_METRICS protocol=1 allocations=");
    try stderr.writeStreamingAll(io, allocations);
    try stderr.writeStreamingAll(io, " work=");
    for (work, 0..) |value, index| {
        if (index != 0) try stderr.writeStreamingAll(io, ",");
        const formatted = try std.fmt.bufPrint(&buffer, "{d}", .{value});
        try stderr.writeStreamingAll(io, formatted);
    }
    try stderr.writeStreamingAll(io, "\n");
}

fn decrefResult(result: RetentionResult, host: *abi.RocHost) void {
    result.backing.decref(host);
    result.bytes.decref(host);
    result.owned.decref(host);
    result.shared.decref(host);
    result.source.decref(host);
    result.work.decref(host);
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
