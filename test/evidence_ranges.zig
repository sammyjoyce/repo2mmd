const std = @import("std");

/// Runs the installed CLI against a small Zig repo and checks that each import
/// edge points at the exact file and line of its `@import`, and that a file the
/// plugin rejects becomes a diagnostic in still-valid JSON.
/// The caller (test/main.zig) runs `zig build` first, which installs the plugins.
pub fn run(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing import edge evidence...\n", .{});

    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src/util");
    try tmp.dir.writeFile(.{ .sub_path = "src/util/a.zig", .data = "pub fn a() void {}\n" });
    try tmp.dir.writeFile(.{
        .sub_path = "src/b.zig",
        .data = "// importer\n\nconst a = @import(\"util/a.zig\");\nconst std = @import(\"std\");\n",
    });

    // More declarations than the scheduler accepts from one file.
    var big = std.ArrayList(u8){};
    defer big.deinit(allocator);
    for (0..1001) |i| try big.print(allocator, "fn f{d}() void {{}}\n", .{i});
    try tmp.dir.writeFile(.{ .sub_path = "src/big.zig", .data = big.items });

    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    const binary_path = try std.fs.path.join(allocator, &.{ cwd, "zig-out", "bin", "repo2mmd" });
    defer allocator.free(binary_path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "--cache-mode", "off", "generate", root, "--format", "json" },
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const edges = parsed.value.object.get("graph").?.object.get("edges").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), edges.len);

    try expectImportEvidence(edges, "file_src/util/a.zig", "Static", 3);
    try expectImportEvidence(edges, "file_std", "Comptime", 4);

    const diagnostics = parsed.value.object.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqualStrings("R2M-SKIPPED-FILE", diagnostics[0].object.get("id").?.string);
    try std.testing.expectEqualStrings("src/big.zig", diagnostics[0].object.get("file").?.string);
    std.debug.print("✓ Import edges carry source path and line evidence\n", .{});
}

fn expectImportEvidence(edges: []const std.json.Value, target: []const u8, certainty: []const u8, line: i64) !void {
    for (edges) |edge_value| {
        const edge = edge_value.object;
        if (!std.mem.eql(u8, edge.get("dst").?.string, target)) continue;

        try std.testing.expectEqualStrings("file_src/b.zig", edge.get("src").?.string);
        try std.testing.expectEqualStrings("Imports", edge.get("rel").?.string);
        try std.testing.expectEqualStrings(certainty, edge.get("certainty").?.string);

        const paths = edge.get("evidence_paths").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), paths.len);
        try std.testing.expectEqualStrings("src/b.zig", paths[0].string);

        const lines = edge.get("evidence_lines").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), lines.len);
        try std.testing.expectEqual(line, lines[0].integer);
        return;
    }
    std.debug.print("No edge to {s}\n", .{target});
    return error.MissingEdge;
}
