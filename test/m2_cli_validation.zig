const std = @import("std");

pub fn run(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing CLI diagram emission with reference counts validation...\n", .{});

    try testSyntheticRepoCounts(allocator);
    try testFixtureCounts(allocator);
    try testTypeScriptCounts(allocator);

    std.debug.print("✓ All CLI validation tests passed\n", .{});
}

fn testSyntheticRepoCounts(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing synthetic repository reference counts...\n", .{});

    const synth_repo_path = try std.fs.cwd().realpathAlloc(allocator, "test_synth_repo");
    defer allocator.free(synth_repo_path);

    // Expected: 3 nodes (main.zig, auth.zig, database.zig), 2 edges (main->auth, main->database)
    const expected_nodes = 3;
    const expected_edges = 2;

    const result = try runCli(allocator, synth_repo_path, "json");
    defer allocator.free(result);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const manifest = root.get("manifest").?.object;
    const graph = root.get("graph").?.object;

    const nodes_array = graph.get("nodes").?.array.items;
    const edges_array = graph.get("edges").?.array.items;

    const file_node_count = countFileNodes(nodes_array);
    const import_edge_count = try countFileImportEdges(allocator, nodes_array, edges_array);

    // Validate counts match expected values when focusing on file-level graph structure
    try validateCount("synthetic repo file nodes", file_node_count, expected_nodes, 1);
    try validateCount("synthetic repo import edges", import_edge_count, expected_edges, 1);

    // Ensure manifest metadata remains consistent with total graph entries
    const manifest_nodes_total = @as(usize, @intCast(manifest.get("node_count").?.integer));
    const manifest_edges_total = @as(usize, @intCast(manifest.get("edge_count").?.integer));
    try std.testing.expectEqual(manifest_nodes_total, nodes_array.len);
    try std.testing.expectEqual(manifest_edges_total, edges_array.len);

    std.debug.print("    ✓ Synthetic repository counts validated\n", .{});
}

fn testFixtureCounts(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing mixed fixtures reference counts...\n", .{});

    const fixtures_path = try std.fs.cwd().realpathAlloc(allocator, "test/fixtures");
    defer allocator.free(fixtures_path);

    // Expected: 11 nodes total (mixed languages), minimal edges
    const expected_nodes = 11;
    const expected_edges_min = 0;
    const expected_edges_max = 5; // Allow some flexibility

    const result = try runCli(allocator, fixtures_path, "json");
    defer allocator.free(result);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const graph = root.get("graph").?.object;
    const nodes_array = graph.get("nodes").?.array.items;
    const edges_array = graph.get("edges").?.array.items;

    const file_node_count = countFileNodes(nodes_array);
    try validateCount("fixtures file nodes", file_node_count, expected_nodes, 1);

    const import_edge_count = try countFileImportEdges(allocator, nodes_array, edges_array);

    // For edges, allow a range since different language parsers might find different relationships
    if (import_edge_count < expected_edges_min or import_edge_count > expected_edges_max) {
        std.debug.print("    ❌ Fixtures edges {d} outside expected range [{d}, {d}]\n", .{ actual_edges, expected_edges_min, expected_edges_max });
        return error.TestFailed;
    }

    std.debug.print("    ✓ Mixed fixtures counts validated\n", .{});
}

fn testTypeScriptCounts(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing TypeScript fixtures reference counts...\n", .{});

    const ts_path = try std.fs.cwd().realpathAlloc(allocator, "test/fixtures/typescript");
    defer allocator.free(ts_path);

    // Expected: 3 nodes (index.ts, auth.ts, database.ts)
    const expected_nodes = 3;

    const result = try runCli(allocator, ts_path, "json");
    defer allocator.free(result);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const graph = root.get("graph").?.object;
    const nodes_array = graph.get("nodes").?.array.items;

    const file_node_count = countFileNodes(nodes_array);

    try validateCount("typescript file nodes", file_node_count, expected_nodes, 1);

    std.debug.print("    ✓ TypeScript fixtures counts validated\n", .{});
}

fn validateCount(name: []const u8, actual: usize, expected: usize, tolerance_percent: usize) !void {
    const tolerance = @max(1, expected * tolerance_percent / 100);
    const min_expected = if (expected > tolerance) expected - tolerance else 0;
    const max_expected = expected + tolerance;

    if (actual < min_expected or actual > max_expected) {
        std.debug.print("    ❌ {s}: {d} outside expected range [{d}, {d}] (±{d}%)\n", .{ name, actual, min_expected, max_expected, tolerance_percent });
        return error.TestFailed;
    }

    std.debug.print("    ✓ {s}: {d} (expected {d} ±{d}%)\n", .{ name, actual, expected, tolerance_percent });
}

fn getBinaryPath(allocator: std.mem.Allocator) ![]const u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, "zig-out", "bin", "repo2mmd" });
}

fn clearCacheDir(root_path: []const u8) void {
    std.fs.cwd().deleteTree(".repo2mmd") catch {};

    var root_dir = std.fs.openDirAbsolute(root_path, .{ .iterate = true }) catch return;
    defer root_dir.close();
    root_dir.deleteTree(".repo2mmd") catch {};
}

fn runCli(allocator: std.mem.Allocator, root_path: []const u8, format: []const u8) ![]const u8 {
    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);

    clearCacheDir(root_path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--root", root_path, "--format", format },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        clearCacheDir(root_path);
        std.debug.print("CLI failed with stderr: {s}\n", .{result.stderr});
        return error.TestFailed;
    }

    // Extract the actual filename from stderr message, accepting either manifest or graph wording
    const markers = [_][]const u8{
        "JSON manifest written to ",
        "JSON graph written to ",
    };

    var filename_slice: ?[]const u8 = null;
    for (markers) |marker| {
        if (std.mem.indexOf(u8, result.stderr, marker)) |marker_start| {
            const filename_start = marker_start + marker.len;
            if (std.mem.indexOf(u8, result.stderr[filename_start..], " ")) |rel_end| {
                filename_slice = result.stderr[filename_start .. filename_start + rel_end];
                break;
            }
        }
    }

    const actual_filename = filename_slice orelse return error.TestFailed;

    const json_file = try std.fs.openFileAbsolute(actual_filename, .{});
    defer json_file.close();
    const contents = try json_file.readToEndAlloc(allocator, 1024 * 1024);
    clearCacheDir(root_path);
    return contents;
}

test "M2CliValidation.validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try run(allocator);
}

const EdgePair = struct {
    src: []const u8,
    dst: []const u8,
};

fn countFileNodes(nodes: []const std.json.Value) usize {
    var count: usize = 0;
    for (nodes) |node| {
        const kind = node.object.get("kind").?.string;
        if (std.mem.eql(u8, kind, "File") or std.mem.eql(u8, kind, "Module")) {
            count += 1;
        }
    }
    return count;
}

fn countFileImportEdges(
    allocator: std.mem.Allocator,
    nodes: []const std.json.Value,
    edges: []const std.json.Value,
) !usize {
    var file_ids = try std.ArrayList([]const u8).initCapacity(allocator, nodes.len);
    defer file_ids.deinit(allocator);

    for (nodes) |node| {
        const kind = node.object.get("kind").?.string;
        if (std.mem.eql(u8, kind, "File") or std.mem.eql(u8, kind, "Module")) {
            try file_ids.append(allocator, node.object.get("id").?.string);
        }
    }

    var pairs = try std.ArrayList(EdgePair).initCapacity(allocator, edges.len);
    defer pairs.deinit(allocator);

    for (edges) |edge| {
        const rel = edge.object.get("rel").?.string;
        if (!std.mem.eql(u8, rel, "Imports")) continue;

        const src = edge.object.get("src").?.string;
        const dst = edge.object.get("dst").?.string;

        if (!containsId(file_ids.items, src) or !containsId(file_ids.items, dst)) continue;

        if (!hasEdgePair(pairs.items, src, dst)) {
            try pairs.append(allocator, .{ .src = src, .dst = dst });
        }
    }

    return pairs.items.len;
}

fn containsId(ids: []const []const u8, target: []const u8) bool {
    for (ids) |id| {
        if (std.mem.eql(u8, id, target)) return true;
    }
    return false;
}

fn hasEdgePair(pairs: []const EdgePair, src: []const u8, dst: []const u8) bool {
    for (pairs) |pair| {
        if (std.mem.eql(u8, pair.src, src) and std.mem.eql(u8, pair.dst, dst)) {
            return true;
        }
    }
    return false;
}
