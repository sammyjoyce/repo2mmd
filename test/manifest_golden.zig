const std = @import("std");

fn getBinaryPath(allocator: std.mem.Allocator) ![]const u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, "zig-out", "bin", "repo2mmd" });
}

pub fn run(allocator: std.mem.Allocator) !void {
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    // Minimal workspace; discovery should find no supported source files yet.
    try tmp.dir.writeFile(.{ .sub_path = "README.md", .data = "demo\n" });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);
    try ensureBinary(allocator, binary_path);

    const output_file_path = try std.fmt.allocPrint(allocator, "{s}.json", .{std.fs.path.basename(root_path)});
    defer allocator.free(output_file_path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--root", root_path, "--format", "json", "--output", output_file_path },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);

    // Read JSON from output file (created in current directory)
    const json_content = try std.fs.cwd().readFileAlloc(allocator, output_file_path, 1024 * 1024);
    defer allocator.free(json_content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const root_object = root.object;
    const schema_version = root_object.get("schema_version").?.integer;
    try std.testing.expectEqual(@as(i64, 1), schema_version);

    const graph = root_object.get("graph").?.object;
    const nodes = graph.get("nodes").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), nodes.len);

    const edges = graph.get("edges").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), edges.len);

    const manifest = root_object.get("manifest").?.object;
    try std.testing.expectEqual(@as(i64, 0), manifest.get("node_count").?.integer);
    try std.testing.expectEqual(@as(i64, 0), manifest.get("edge_count").?.integer);
    try std.testing.expectEqual(@as(i64, 0), manifest.get("unresolved_refs").?.integer);
    try std.testing.expectEqual(@as(i64, 0), manifest.get("cache_hits").?.integer);
    try std.testing.expectEqual(@as(i64, 0), manifest.get("cache_misses").?.integer);

    const input_root = manifest.get("input_root").?.string;
    try std.testing.expectEqualStrings(root_path, input_root);

    const graph_type = manifest.get("graph_type").?.string;
    try std.testing.expectEqualStrings("Deps", graph_type);

    const diagnostics = root_object.get("diagnostics").?.array.items;
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
        return ManifestGoldenError.BuildFailed;
    }
}

const ManifestGoldenError = error{BuildFailed};
