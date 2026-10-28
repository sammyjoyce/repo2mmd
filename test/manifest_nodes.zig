const std = @import("std");

fn getBinaryPath(allocator: std.mem.Allocator) ![]const u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, "zig-out", "bin", "repo2mmd" });
}

pub fn run(allocator: std.mem.Allocator) !void {
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/a.zig", .data = "const std = @import(\"std\");\n" });
    try tmp.dir.writeFile(.{ .sub_path = "src/b.zig", .data = "const std = @import(\"std\");\n" });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    // Use absolute paths like the CLI actually does
    const path_a = try std.fs.path.join(allocator, &.{ root_path, "src", "a.zig" });
    defer allocator.free(path_a);
    const path_b = try std.fs.path.join(allocator, &.{ root_path, "src", "b.zig" });
    defer allocator.free(path_b);

    var paths = [_][]const u8{ path_a, path_b };
    if (std.mem.lessThan(u8, paths[1], paths[0])) {
        const tmp_path = paths[0];
        paths[0] = paths[1];
        paths[1] = tmp_path;
    }

    var ids: [2]?[]u8 = .{ null, null };
    defer for (ids) |maybe_id| {
        if (maybe_id) |id| allocator.free(id);
    };

    for (paths, 0..) |path, idx| {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(path);
        const hash = hasher.final();
        ids[idx] = try std.fmt.allocPrint(allocator, "{x:0>16}", .{hash});
    }

    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);
    try ensureBinary(binary_path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--root", ".", "--format", "json" },
        .cwd = root_path,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);

    // Extract the actual filename from stderr message
    // stderr format: "JSON manifest written to <filename>.json (X files analyzed)"
    const stderr_start = std.mem.indexOf(u8, result.stderr, "JSON manifest written to ") orelse return error.TestFailed;
    const filename_start = stderr_start + "JSON manifest written to ".len;
    const filename_end = std.mem.indexOf(u8, result.stderr[filename_start..], " ") orelse return error.TestFailed;
    const actual_filename = result.stderr[filename_start .. filename_start + filename_end];

    const json_file = try std.fs.openFileAbsolute(actual_filename, .{});
    defer json_file.close();
    const json_content = try json_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const root_object = root.object;

    const schema_version = root_object.get("schema_version").?.integer;
    try std.testing.expectEqual(@as(i64, 1), schema_version);

    const graph = root_object.get("graph").?.object;
    const nodes = graph.get("nodes").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), nodes.len);

    // Create a map of expected names to their hashes
    var name_to_hash = std.StringHashMap([]const u8).init(allocator);
    defer name_to_hash.deinit();
    try name_to_hash.put("a.zig", ids[0].?);
    try name_to_hash.put("b.zig", ids[1].?);

    for (nodes) |node_value| {
        const node = node_value.object;
        const node_id = node.get("id").?.string;
        const node_name = node.get("name").?.string;

        // Verify that the node name matches one of our expected files
        const expected_hash = name_to_hash.get(node_name) orelse {
            std.debug.print("Unexpected node name: {s}\n", .{node_name});
            return error.UnexpectedNodeName;
        };

        // Verify that the ID matches the expected hash for this name
        try std.testing.expectEqualStrings(expected_hash, node_id);

        const range = node.get("range").?.object;
        try std.testing.expectEqual(@as(i64, 1), range.get("l0").?.integer);
        try std.testing.expectEqual(@as(i64, 1), range.get("c0").?.integer);
    }

    const edges = graph.get("edges").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), edges.len);

    const manifest = root_object.get("manifest").?.object;
    try std.testing.expectEqual(@as(i64, 2), manifest.get("node_count").?.integer);
    try std.testing.expectEqual(@as(i64, 0), manifest.get("edge_count").?.integer);
    try std.testing.expectEqualStrings(root_path, manifest.get("input_root").?.string);
    try std.testing.expectEqualStrings("Deps", manifest.get("graph_type").?.string);

    const diagnostics = root_object.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), diagnostics.len);
}

fn ensureBinary(binary_path: []const u8) !void {
    if (std.fs.cwd().access(binary_path, .{})) |_| {
        return;
    } else |_| {}

    const build_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "zig", "build" },
        .cwd = null,
    });
    defer std.testing.allocator.free(build_result.stdout);
    defer std.testing.allocator.free(build_result.stderr);

    if (build_result.term != .Exited or build_result.term.Exited != 0) {
        return error.BuildFailed;
    }
}
