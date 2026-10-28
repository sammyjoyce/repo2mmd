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
    try tmp.dir.writeFile(.{ .sub_path = "src/a.zig", .data = "pub fn a() void {}\n" });
    try tmp.dir.writeFile(.{ .sub_path = "src/b.zig", .data = "const a = @import(\"a.zig\");\n" });

    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    const path_a = try tmp.dir.realpathAlloc(allocator, "src/a.zig");
    defer allocator.free(path_a);
    const path_b = try tmp.dir.realpathAlloc(allocator, "src/b.zig");
    defer allocator.free(path_b);

    const id_a = try hashPath(allocator, path_a);
    defer allocator.free(id_a);
    const id_b = try hashPath(allocator, path_b);
    defer allocator.free(id_b);

    try ensureBinary();

    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--root", root, "--format", "json" },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Read JSON from output file (default: <root>/<basename>.json)
    const output_file_path = try std.fmt.allocPrint(allocator, "{s}.json", .{std.fs.path.basename(root)});
    defer allocator.free(output_file_path);

    const json_content = try tmp.dir.readFileAlloc(allocator, output_file_path, 1024 * 1024);
    defer allocator.free(json_content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const root_object = parsed.value.object;
    try std.testing.expectEqual(@as(i64, 1), root_object.get("schema_version").?.integer);

    const graph = root_object.get("graph").?.object;
    const nodes = graph.get("nodes").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), nodes.len);

    // Create a map of expected names to their hashes
    var name_to_hash = std.StringHashMap([]const u8).init(allocator);
    defer name_to_hash.deinit();
    try name_to_hash.put("a.zig", id_a);
    try name_to_hash.put("b.zig", id_b);

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
    }

    const edges = graph.get("edges").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), edges.len);

    // Verify the edge goes from b.zig to a.zig
    const edge = edges[0].object;
    const src_id = edge.get("src").?.string;
    const dst_id = edge.get("dst").?.string;
    const rel = edge.get("rel").?.string;

    try std.testing.expectEqualStrings("imports", rel);
    try std.testing.expectEqualStrings(id_b, src_id); // b.zig imports
    try std.testing.expectEqualStrings(id_a, dst_id); // a.zig

    const manifest = root_object.get("manifest").?.object;
    try std.testing.expectEqual(@as(i64, 2), manifest.get("node_count").?.integer);
    try std.testing.expectEqual(@as(i64, 1), manifest.get("edge_count").?.integer);
    try std.testing.expectEqualStrings(root, manifest.get("input_root").?.string);
    try std.testing.expectEqualStrings("Deps", manifest.get("graph_type").?.string);

    const diagnostics = root_object.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), diagnostics.len);
}

fn hashPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(path);
    const hash = hasher.final();
    return std.fmt.allocPrint(allocator, "{x:0>16}", .{hash});
}

fn ensureBinary() !void {
    const binary_path = "zig-out/bin/repo2mmd";
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
