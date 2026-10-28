const std = @import("std");
const testing = std.testing;

const ir = @import("ir");
const discovery = @import("discovery");
const scheduler = @import("scheduler");

test "ir module exposes init placeholder" {
    try testing.expectError(error.Unimplemented, ir.init());
}

test "discovery scan succeeds on empty directory" {
    var tmp = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    const root_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root_path);

    const units = try discovery.scan(testing.allocator, root_path);
    defer discovery.deinitUnits(testing.allocator, units);

    try testing.expectEqual(@as(usize, 0), units.len);
}

test "scheduler module exposes run placeholder" {
    try testing.expectError(error.Unimplemented, scheduler.run());
}
