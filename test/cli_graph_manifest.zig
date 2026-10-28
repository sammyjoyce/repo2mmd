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
    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "const std = @import(\"std\");\n" });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    // Use absolute path like the CLI actually does
    const file_path = try std.fs.path.join(allocator, &.{ root_path, "src", "main.zig" });
    defer allocator.free(file_path);

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(file_path);
    const id_hash = hasher.final();
    const node_id = try std.fmt.allocPrint(allocator, "{x:0>16}", .{id_hash});
    defer allocator.free(node_id);

    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);
    try ensureBinary(allocator, binary_path);

    // Get the project root to find plugins (binary is in zig-out/bin, we need to go up two levels to project root)
    const bin_dir = try std.fs.cwd().realpathAlloc(allocator, std.fs.path.dirname(binary_path).?);
    defer allocator.free(bin_dir);
    const project_root_path = try std.fs.path.join(allocator, &.{ bin_dir, "..", ".." });
    defer allocator.free(project_root_path);
    const project_root = try std.fs.cwd().realpathAlloc(allocator, project_root_path);
    defer allocator.free(project_root);
    const plugin_dir = try std.fs.path.join(allocator, &.{ project_root, "zig-out", "lib", "repo2mmd", "plugins" });
    defer allocator.free(plugin_dir);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--root", ".", "--format", "json", "--plugin-dir", plugin_dir },
        .cwd = root_path,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("CLI failed with stderr: {s}\n", .{result.stderr});
        return error.TestFailed;
    }

    // Extract the actual filename from stderr message
    // stderr format: "JSON graph written to <filename>.json (X files analyzed)"
    const stderr_start = std.mem.indexOf(u8, result.stderr, "JSON graph written to ") orelse {
        // Try stdout as well since the message might be going there
        const stdout_start = std.mem.indexOf(u8, result.stdout, "JSON graph written to ") orelse {
            return error.TestFailed;
        };
        const filename_start = stdout_start + "JSON manifest written to ".len;
        const filename_end = std.mem.indexOf(u8, result.stdout[filename_start..], " ") orelse return error.TestFailed;
        const actual_filename = result.stdout[filename_start .. filename_start + filename_end];

        const json_file = try std.fs.cwd().openFile(actual_filename, .{});
        defer json_file.close();
        const json_content = try json_file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(json_content);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;
        try std.testing.expectEqual(@as(i64, 1), root.get("schema_version").?.integer);

        const graph = root.get("graph").?.object;
        const nodes = graph.get("nodes").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), nodes.len);

        const node = nodes[0].object;
        try std.testing.expectEqualStrings(node_id, node.get("id").?.string);
        try std.testing.expectEqualStrings("main.zig", node.get("name").?.string);

        const edges = graph.get("edges").?.array.items;
        try std.testing.expectEqual(@as(usize, 0), edges.len);

        const manifest = root.get("manifest").?.object;
        try std.testing.expectEqual(@as(i64, 1), manifest.get("node_count").?.integer);
        try std.testing.expectEqual(@as(i64, 0), manifest.get("edge_count").?.integer);
        try std.testing.expectEqualStrings(root_path, manifest.get("input_root").?.string);
        try std.testing.expectEqualStrings("Deps", manifest.get("graph_type").?.string);

        const diagnostics = root.get("diagnostics").?.array.items;
        try std.testing.expectEqual(@as(usize, 0), diagnostics.len);

        return;
    };
    const filename_start = stderr_start + "JSON manifest written to ".len;
    const filename_end = std.mem.indexOf(u8, result.stderr[filename_start..], " ") orelse return error.TestFailed;
    const actual_filename = result.stderr[filename_start .. filename_start + filename_end];

    const json_file = try std.fs.cwd().openFile(actual_filename, .{});
    defer json_file.close();
    const json_content = try json_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expectEqual(@as(i64, 1), root.get("schema_version").?.integer);

    const graph = root.get("graph").?.object;
    const nodes = graph.get("nodes").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), nodes.len);

    const node = nodes[0].object;
    try std.testing.expectEqualStrings(node_id, node.get("id").?.string);
    try std.testing.expectEqualStrings("main.zig", node.get("name").?.string);

    const edges = graph.get("edges").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), edges.len);

    const manifest = root.get("manifest").?.object;
    try std.testing.expectEqual(@as(i64, 1), manifest.get("node_count").?.integer);
    try std.testing.expectEqual(@as(i64, 0), manifest.get("edge_count").?.integer);
    try std.testing.expectEqualStrings(root_path, manifest.get("input_root").?.string);
    try std.testing.expectEqualStrings("Deps", manifest.get("graph_type").?.string);

    const diagnostics = root.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), diagnostics.len);
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
        return ManifestCliError.BuildFailed;
    }
}

const ManifestCliError = error{BuildFailed};
