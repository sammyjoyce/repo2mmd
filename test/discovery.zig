const std = @import("std");
const testing = std.testing;
const discovery = @import("discovery");

test "scan returns source units and detects languages" {
    var tmp = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.makePath("lib");
    try tmp.dir.makePath("web");

    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "const std = @import(\"std\");\n" });
    try tmp.dir.writeFile(.{ .sub_path = "lib/helpers.c", .data = "int answer(void){return 42;}\n" });
    try tmp.dir.writeFile(.{ .sub_path = "web/index.ts", .data = "export const value = 1;\n" });

    const root_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root_path);

    const units = try discovery.scan(testing.allocator, root_path);
    defer discovery.deinitUnits(testing.allocator, units);

    try testing.expectEqual(@as(usize, 3), units.len);

    const zig_unit = findUnit(units, "src/main.zig");
    try testing.expect(zig_unit != null);
    try testing.expectEqual(discovery.Language.Zig, zig_unit.?.lang);

    const c_unit = findUnit(units, "lib/helpers.c");
    try testing.expect(c_unit != null);
    try testing.expectEqual(discovery.Language.C, c_unit.?.lang);

    const ts_unit = findUnit(units, "web/index.ts");
    try testing.expect(ts_unit != null);
    try testing.expectEqual(discovery.Language.Ts, ts_unit.?.lang);
}

test "scan sorts units by path and skips hidden and build directories" {
    var tmp = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    const files = [_][]const u8{ "z.zig", "b/a.zig", "a.zig", ".zig-cache/o/x.zig", "zig-out/y.zig", "node_modules/m.ts", ".git/hooks.zig" };
    for (files) |path| {
        if (std.fs.path.dirname(path)) |dir| try tmp.dir.makePath(dir);
        try tmp.dir.writeFile(.{ .sub_path = path, .data = "" });
    }

    const root_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root_path);

    const units = try discovery.scan(testing.allocator, root_path);
    defer discovery.deinitUnits(testing.allocator, units);

    const expected = [_][]const u8{ "a.zig", "b/a.zig", "z.zig" };
    try testing.expectEqual(expected.len, units.len);
    for (expected, units) |path, unit| try testing.expectEqualStrings(path, unit.path);
}

test "deinitUnits properly cleans up memory" {
    var tmp = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "test.zig", .data = "const std = @import(\"std\");\n" });

    const root_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root_path);

    const units = try discovery.scan(testing.allocator, root_path);
    try testing.expect(units.len > 0);

    // This should not cause memory leaks
    discovery.deinitUnits(testing.allocator, units);
}

fn findUnit(units: []const discovery.SourceUnit, path: []const u8) ?discovery.SourceUnit {
    for (units) |unit| {
        if (std.mem.eql(u8, unit.path, path)) return unit;
    }
    return null;
}
