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
    try tmp.dir.writeFile(.{ .sub_path = "src/c.zig", .data = "const a = @import(\"a.zig\");\n" });

    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    const path_a = try tmp.dir.realpathAlloc(allocator, "src/a.zig");
    defer allocator.free(path_a);
    const path_b = try tmp.dir.realpathAlloc(allocator, "src/b.zig");
    defer allocator.free(path_b);
    const path_c = try tmp.dir.realpathAlloc(allocator, "src/c.zig");
    defer allocator.free(path_c);

    const id_a = try hashPath(allocator, path_a);
    defer allocator.free(id_a);
    const id_b = try hashPath(allocator, path_b);
    defer allocator.free(id_b);
    const id_c = try hashPath(allocator, path_c);
    defer allocator.free(id_c);

    try ensureBinary();

    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--root", root, "--format", "json" },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Read JSON from output file (default: <cwd_name>.json)
    const output_file_path = try std.fmt.allocPrint(allocator, "{s}.json", .{std.fs.path.basename(root)});
    defer allocator.free(output_file_path);

    const json_content = try tmp.dir.readFileAlloc(allocator, output_file_path, 1024 * 1024);
    defer allocator.free(json_content);

    const manifest = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer manifest.deinit();

    const graph = manifest.value.object.get("graph").?.object;
    const edges = graph.get("edges").?.array.items;
    // Both b.zig and c.zig import from a.zig, so expect 2 edges
    try std.testing.expectEqual(@as(usize, 2), edges.len);

    // Basic verification that both edges import a.zig
    for (edges) |edge_value| {
        const edge = edge_value.object;
        const dst = edge.get("dst").?.string;
        try std.testing.expectEqualStrings(id_a, dst);
    }
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
