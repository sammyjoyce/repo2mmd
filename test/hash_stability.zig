const std = @import("std");

pub fn run(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing hash stability and deterministic output...\n", .{});

    // Create multiple test repositories with different structures
    try testSyntheticRepoStability(allocator);
    try testFileOrderIndependence(allocator);
    try testMultipleRunConsistency(allocator);
    try testHashDeterminism(allocator);

    std.debug.print("✓ All hash stability tests passed\n", .{});
}

fn testSyntheticRepoStability(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing synthetic repository stability...\n", .{});

    // Create a temporary directory
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    // Create the same structure as our test_synth_repo
    try tmp.dir.makePath("src");

    const main_content =
        \\const std = @import("std");
        \\const auth = @import("auth.zig");
        \\const database = @import("database.zig");
        \\
        \\pub fn main() !void {
        \\    const user = auth.init("admin", "password");
        \\    _ = user.authenticate("password");
        \\    const db = try database.connect("localhost");
        \\    _ = db.query("SELECT * FROM users");
        \\}
    ;

    const auth_content =
        \\const std = @import("std");
        \\
        \\pub const User = struct {
        \\    name: []const u8,
        \\    password: []const u8,
        \\
        \\    pub fn init(name: []const u8, password: []const u8) User {
        \\        return User{
        \\            .name = name,
        \\            .password = password,
        \\        };
        \\    }
        \\
        \\    pub fn authenticate(self: User, password: []const u8) bool {
        \\        return std.mem.eql(u8, self.password, password);
        \\    }
        \\};
    ;

    const database_content =
        \\const std = @import("std");
        \\
        \\pub const Database = struct {
        \\    url: []const u8,
        \\
        \\    pub fn connect(url: []const u8) !Database {
        \\        if (url.len == 0) {
        \\            return error.EmptyUrl;
        \\        }
        \\        return Database{
        \\            .url = url,
        \\        };
        \\    }
        \\
        \\    pub fn query(self: Database, sql: []const u8) ![]const u8 {
        \\        _ = self;
        \\        _ = sql;
        \\        return "result";
        \\    }
        \\};
    ;

    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = main_content });
    try tmp.dir.writeFile(.{ .sub_path = "src/auth.zig", .data = auth_content });
    try tmp.dir.writeFile(.{ .sub_path = "src/database.zig", .data = database_content });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    // Run the CLI multiple times and compare results
    var results = try std.ArrayList([]const u8).initCapacity(allocator, 3);
    defer {
        for (results.items) |result| allocator.free(result);
        results.deinit(allocator);
    }

    // Run 3 times to ensure consistency
    for (0..3) |_| {
        const result = try runCli(allocator, root_path);
        try results.append(allocator, result);
    }

    // Compare all results, ignoring cache statistics that may vary between runs
    var sanitized_results = try std.ArrayList([]const u8).initCapacity(allocator, results.items.len);
    defer {
        for (sanitized_results.items) |item| allocator.free(item);
        sanitized_results.deinit(allocator);
    }

    for (results.items) |item| {
        const sanitized = try stripCacheStats(allocator, item);
        try sanitized_results.append(allocator, sanitized);
    }

    for (1..sanitized_results.items.len) |i| {
        try std.testing.expectEqualStrings(sanitized_results.items[0], sanitized_results.items[i]);
    }

    // The actual output will be validated by comparing structure and key fields
    // rather than exact string matching since timestamps and other dynamic fields
    // will differ between runs

    // Parse and validate JSON structure consistency across runs
    for (results.items) |result| {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Validate required fields exist
        try std.testing.expect(root.contains("schema_version"));
        try std.testing.expect(root.contains("graph"));
        try std.testing.expect(root.contains("manifest"));
        try std.testing.expect(root.contains("diagnostics"));

        // Validate graph structure
        const graph = root.get("graph").?.object;
        try std.testing.expect(graph.contains("nodes"));
        try std.testing.expect(graph.contains("edges"));

        const nodes = graph.get("nodes").?.array.items;
        const edges = graph.get("edges").?.array.items;

        var file_ids = try std.ArrayList([]const u8).initCapacity(allocator, nodes.len);
        defer file_ids.deinit(allocator);

        for (nodes) |node| {
            const kind = node.object.get("kind").?.string;
            if (std.mem.eql(u8, kind, "File") or std.mem.eql(u8, kind, "Module")) {
                try file_ids.append(allocator, node.object.get("id").?.string);
            }
        }

        try std.testing.expectEqual(@as(usize, 3), file_ids.items.len);

        var import_pairs = try std.ArrayList(EdgePair).initCapacity(allocator, edges.len);
        defer import_pairs.deinit(allocator);

        for (edges) |edge| {
            const rel = edge.object.get("rel").?.string;
            if (!std.mem.eql(u8, rel, "Imports")) continue;

            const src = edge.object.get("src").?.string;
            const dst = edge.object.get("dst").?.string;

            if (!containsId(file_ids.items, src) or !containsId(file_ids.items, dst)) continue;

            if (!hasEdgePair(import_pairs.items, src, dst)) {
                try import_pairs.append(allocator, .{ .src = src, .dst = dst });
            }
        }

        try std.testing.expectEqual(@as(usize, 2), import_pairs.items.len);

        // Verify file-level node IDs are unique
        for (file_ids.items, 0..) |id, i| {
            for (file_ids.items[i + 1 ..]) |other| {
                try std.testing.expect(!std.mem.eql(u8, id, other));
            }
        }
    }

    std.debug.print("    ✓ Synthetic repository produces stable output\n", .{});
}

fn testFileOrderIndependence(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing file order independence...\n", .{});

    // Create two repositories with same files but different creation order
    var tmp1 = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp1.cleanup();

    var tmp2 = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp2.cleanup();

    // Repository 1: Create files in order A, B, C
    try tmp1.dir.makePath("src");
    try tmp1.dir.writeFile(.{ .sub_path = "src/a.zig", .data = "const b = @import(\"b.zig\");" });
    try tmp1.dir.writeFile(.{ .sub_path = "src/b.zig", .data = "const c = @import(\"c.zig\");" });
    try tmp1.dir.writeFile(.{ .sub_path = "src/c.zig", .data = "pub fn foo() void {}" });

    // Repository 2: Create files in order C, B, A
    try tmp2.dir.makePath("src");
    try tmp2.dir.writeFile(.{ .sub_path = "src/c.zig", .data = "pub fn foo() void {}" });
    try tmp2.dir.writeFile(.{ .sub_path = "src/b.zig", .data = "const c = @import(\"c.zig\");" });
    try tmp2.dir.writeFile(.{ .sub_path = "src/a.zig", .data = "const b = @import(\"b.zig\");" });

    const root_path1 = try tmp1.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path1);
    const root_path2 = try tmp2.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path2);

    // Run CLI on both repositories
    const result1 = try runCli(allocator, root_path1);
    defer allocator.free(result1);
    const result2 = try runCli(allocator, root_path2);
    defer allocator.free(result2);

    // Parse both results and compare structure
    var parsed1 = try std.json.parseFromSlice(std.json.Value, allocator, result1, .{});
    defer parsed1.deinit();
    var parsed2 = try std.json.parseFromSlice(std.json.Value, allocator, result2, .{});
    defer parsed2.deinit();

    const root1 = parsed1.value.object;
    const root2 = parsed2.value.object;

    // Compare structure (not exact values since paths differ)
    try std.testing.expectEqual(root1.get("schema_version").?.integer, root2.get("schema_version").?.integer);

    const graph1 = root1.get("graph").?.object;
    const graph2 = root2.get("graph").?.object;

    const nodes1 = graph1.get("nodes").?.array.items;
    const nodes2 = graph2.get("nodes").?.array.items;
    const edges1 = graph1.get("edges").?.array.items;
    const edges2 = graph2.get("edges").?.array.items;

    try std.testing.expectEqual(nodes1.len, nodes2.len);
    try std.testing.expectEqual(edges1.len, edges2.len);

    // Verify node names are the same (order may differ)
    var node_names1 = try allocator.alloc([]const u8, nodes1.len);
    defer allocator.free(node_names1);
    var node_names2 = try allocator.alloc([]const u8, nodes2.len);
    defer allocator.free(node_names2);

    for (nodes1, 0..) |node, i| {
        node_names1[i] = node.object.get("name").?.string;
    }
    for (nodes2, 0..) |node, i| {
        node_names2[i] = node.object.get("name").?.string;
    }

    // Sort both arrays and compare
    std.mem.sort([]const u8, node_names1, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    std.mem.sort([]const u8, node_names2, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Compare string content, not pointers
    try std.testing.expectEqual(node_names1.len, node_names2.len);
    for (node_names1, node_names2) |name1, name2| {
        try std.testing.expectEqualStrings(name1, name2);
    }

    std.debug.print("    ✓ File creation order does not affect output structure\n", .{});
}

fn testMultipleRunConsistency(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing multiple run consistency...\n", .{});

    // Use the existing synthetic repository
    const synth_repo_path = try std.fs.cwd().realpathAlloc(allocator, "test_synth_repo");
    defer allocator.free(synth_repo_path);

    var results = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    defer {
        for (results.items) |result| allocator.free(result);
        results.deinit(allocator);
    }

    // Run CLI 5 times
    for (0..5) |_| {
        const result = try runCli(allocator, synth_repo_path);
        try results.append(allocator, result);
    }

    // Compare all results, ignoring cache statistics that may vary between runs
    var sanitized_results = try std.ArrayList([]const u8).initCapacity(allocator, results.items.len);
    defer {
        for (sanitized_results.items) |item| allocator.free(item);
        sanitized_results.deinit(allocator);
    }

    for (results.items) |item| {
        const sanitized = try stripCacheStats(allocator, item);
        try sanitized_results.append(allocator, sanitized);
    }

    for (1..sanitized_results.items.len) |i| {
        try std.testing.expectEqualStrings(sanitized_results.items[0], sanitized_results.items[i]);
    }

    // Parse and validate JSON structure consistency
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, results.items[0], .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const manifest = root.get("manifest").?.object;

    // Validate required fields exist
    try std.testing.expect(manifest.contains("schema_version"));
    try std.testing.expect(manifest.contains("graph_type"));
    try std.testing.expect(manifest.contains("node_count"));
    try std.testing.expect(manifest.contains("edge_count"));

    // Validate node and edge counts match actual arrays
    const node_count = @as(usize, @intCast(manifest.get("node_count").?.integer));
    const edge_count = @as(usize, @intCast(manifest.get("edge_count").?.integer));
    const graph = root.get("graph").?.object;
    const nodes = graph.get("nodes").?.array.items;
    const edges = graph.get("edges").?.array.items;

    for (nodes) |node| {
        const kind = node.object.get("kind").?.string;
        const origin = node.object.get("origin_plugin") orelse std.json.Value{ .string = "" };
        const origin_str = switch (origin) {
            .string => origin.string,
            else => "",
        };
        std.debug.print("node kind={s} origin={s}\n", .{ kind, origin_str });
    }
    std.debug.print("node_count={d}\n", .{nodes.len});
    std.debug.print("edge_count={d}\n", .{edges.len});

    try std.testing.expectEqual(node_count, nodes.len);
    try std.testing.expectEqual(edge_count, edges.len);

    // Validate node IDs are unique
    var node_ids = try std.ArrayList([]const u8).initCapacity(allocator, nodes.len);
    defer {
        for (node_ids.items) |id| allocator.free(id);
        node_ids.deinit(allocator);
    }

    for (nodes) |node| {
        const node_id = node.object.get("id").?.string;
        for (node_ids.items) |existing_id| {
            try std.testing.expect(!std.mem.eql(u8, node_id, existing_id));
        }
        try node_ids.append(allocator, try allocator.dupe(u8, node_id));
    }

    std.debug.print("    ✓ Multiple runs produce consistent results\n", .{});
}

fn testHashDeterminism(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing hash determinism...\n", .{});

    // Create a simple repository to test hash consistency
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/test.zig", .data = "pub fn hello() void {}" });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    // Calculate expected hash for the file
    const file_path = try std.fs.path.join(allocator, &.{ root_path, "src", "test.zig" });
    defer allocator.free(file_path);

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(file_path);
    const expected_hash = hasher.final();
    const expected_id = try std.fmt.allocPrint(allocator, "{x:0>16}", .{expected_hash});
    defer allocator.free(expected_id);

    // Run CLI and verify the hash matches
    const result = try runCli(allocator, root_path);
    defer allocator.free(result);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const graph = root.get("graph").?.object;
    const nodes = graph.get("nodes").?.array.items;

    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    const actual_id = nodes[0].object.get("id").?.string;

    try std.testing.expectEqualStrings(expected_id, actual_id);

    std.debug.print("    ✓ Hash generation is deterministic\n", .{});
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

fn runCli(allocator: std.mem.Allocator, root_path: []const u8) ![]const u8 {
    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);
    try ensureBinary(allocator, binary_path);

    // Calculate plugin directory
    const bin_dir = try std.fs.cwd().realpathAlloc(allocator, std.fs.path.dirname(binary_path).?);
    defer allocator.free(bin_dir);
    const project_root_path = try std.fs.path.join(allocator, &.{ bin_dir, "..", ".." });
    defer allocator.free(project_root_path);
    const project_root = try std.fs.cwd().realpathAlloc(allocator, project_root_path);
    defer allocator.free(project_root);
    const plugin_dir = try std.fs.path.join(allocator, &.{ project_root, "zig-out", "lib", "repo2mmd", "plugins" });
    defer allocator.free(plugin_dir);

    clearCacheDir(root_path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--root", root_path, "--format", "json", "--plugin-dir", plugin_dir },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        clearCacheDir(root_path);
        std.debug.print("CLI failed with stderr: {s}\n", .{result.stderr});
        return error.TestFailed;
    }

    // Extract the actual filename from stderr message
    const stderr_start = std.mem.indexOf(u8, result.stderr, "JSON graph written to ") orelse return error.TestFailed;
    const filename_start = stderr_start + "JSON graph written to ".len;
    const filename_end = std.mem.indexOf(u8, result.stderr[filename_start..], " ") orelse return error.TestFailed;
    const actual_filename = result.stderr[filename_start .. filename_start + filename_end];

    const json_file = try std.fs.openFileAbsolute(actual_filename, .{});
    defer json_file.close();
    const contents = try json_file.readToEndAlloc(allocator, 1024 * 1024);
    clearCacheDir(root_path);
    return contents;
}

fn ensureBinary(allocator: std.mem.Allocator, binary_path: []const u8) !void {
    if (std.fs.cwd().access(binary_path, .{})) |_| {
        return;
    } else |_| {}

    const build_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build" },
        .cwd = null,
    });
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);

    if (build_result.term != .Exited or build_result.term.Exited != 0) {
        return error.BuildFailed;
    }
}

test "HashStability.validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try run(allocator);
}

fn normalizeJson(allocator: std.mem.Allocator, json_str: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    var normalized = try std.ArrayList(u8).initCapacity(allocator, json_str.len);
    const writer = normalized.writer();

    try std.json.stringify(parsed.value, .{ .whitespace = .indent_2 }, writer);

    return normalized.toOwnedSlice(allocator);
}

fn stripCacheStats(allocator: std.mem.Allocator, json_str: []const u8) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, json_str.len);
    var iter = std.mem.splitScalar(u8, json_str, '\n');
    var first = true;

    while (iter.next()) |line| {
        if (std.mem.indexOf(u8, line, "\"cache_hits\"") != null or
            std.mem.indexOf(u8, line, "\"cache_misses\"") != null)
        {
            continue;
        }

        if (!first) try buffer.append(allocator, '\n');
        first = false;
        try buffer.appendSlice(allocator, line);
    }

    return buffer.toOwnedSlice(allocator);
}

const EdgePair = struct {
    src: []const u8,
    dst: []const u8,
};

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
