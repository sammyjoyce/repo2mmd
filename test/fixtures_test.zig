const std = @import("std");
const testing = std.testing;

const FixtureCase = struct {
    language: []const u8,
    fixture_path: []const u8,
    golden_json: []const u8,
    golden_mmd: []const u8,
    expected_nodes: usize,
    expected_edges: usize,
};

const fixture_cases = [_]FixtureCase{
    .{
        .language = "Zig",
        .fixture_path = "test/fixtures/zig",
        .golden_json = "test/golden/zig_deps_golden.json",
        .golden_mmd = "test/golden/zig_deps_golden.mmd",
        .expected_nodes = 3,
        .expected_edges = 2,
    },
    .{
        .language = "Ts",
        .fixture_path = "test/fixtures/typescript",
        .golden_json = "test/golden/typescript_deps_golden.json",
        .golden_mmd = "test/golden/typescript_deps_golden.mmd",
        .expected_nodes = 13,
        .expected_edges = 103,
    },
};

test "fixture files exist and are readable" {
    for (fixture_cases) |case| {
        // Check fixture directory exists
        var fixture_dir = std.fs.cwd().openDir(case.fixture_path, .{}) catch |err| {
            std.debug.print("Failed to open fixture directory for {s}: {}\n", .{ case.language, err });
            return err;
        };
        defer fixture_dir.close();

        // Check golden JSON file exists
        const json_file = std.fs.cwd().openFile(case.golden_json, .{}) catch |err| {
            std.debug.print("Failed to open golden JSON for {s}: {}\n", .{ case.language, err });
            return err;
        };
        defer json_file.close();

        // Check golden MMD file exists
        const mmd_file = std.fs.cwd().openFile(case.golden_mmd, .{}) catch |err| {
            std.debug.print("Failed to open golden MMD for {s}: {}\n", .{ case.language, err });
            return err;
        };
        defer mmd_file.close();

        std.debug.print("✓ Fixture files exist for {s}\n", .{case.language});
    }
}

test "golden JSON files have valid structure" {
    const allocator = testing.allocator;

    for (fixture_cases) |case| {
        const contents = try std.fs.cwd().readFileAlloc(allocator, case.golden_json, 1024 * 1024);
        defer allocator.free(contents);

        // Parse as generic JSON to check structure flexibly
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, contents, .{});
        defer parsed.deinit();

        const root_value = parsed.value;
        const root_object = root_value.object;

        if (root_object.get("schema_version")) |schema_version| {
            try testing.expectEqual(@as(i64, 1), schema_version.integer);

            const graph = root_object.get("graph").?.object;
            const nodes = graph.get("nodes").?.array.items;
            const edges = graph.get("edges").?.array.items;

            try testing.expectEqual(case.expected_nodes, nodes.len);
            try testing.expectEqual(case.expected_edges, edges.len);

            const manifest = root_object.get("manifest").?.object;
            try testing.expectEqual(case.expected_nodes, @as(usize, @intCast(manifest.get("node_count").?.integer)));
            try testing.expectEqual(case.expected_edges, @as(usize, @intCast(manifest.get("edge_count").?.integer)));
        } else {
            // Fallback for legacy fixtures still using the v0 schema
            try testing.expect(root_object.get("version") != null);
            try testing.expect(root_object.get("nodes") != null);
            try testing.expect(root_object.get("edges") != null);
            try testing.expectEqualStrings("1.0.0", root_object.get("version").?.string);
            try testing.expectEqual(case.expected_nodes, @as(usize, @intCast(root_object.get("node_count").?.integer)));
            try testing.expectEqual(case.expected_edges, @as(usize, @intCast(root_object.get("edge_count").?.integer)));
        }

        std.debug.print("✓ Golden JSON structure valid for {s}\n", .{case.language});
    }
}

test "golden Mermaid files contain expected elements" {
    for (fixture_cases) |case| {
        const contents = try std.fs.cwd().readFileAlloc(testing.allocator, case.golden_mmd, 1024 * 1024);
        defer testing.allocator.free(contents);

        // Check for basic Mermaid structure
        try testing.expect(std.mem.indexOf(u8, contents, "graph TD") != null);
        try testing.expect(std.mem.indexOf(u8, contents, "main") != null);

        // Check for styling (using individual style statements)
        try testing.expect(std.mem.indexOf(u8, contents, "style") != null);

        std.debug.print("✓ Golden Mermaid structure valid for {s}\n", .{case.language});
    }
}

test "fixture discovery finds expected source files" {
    for (fixture_cases) |case| {
        var fixture_dir = try std.fs.cwd().openDir(case.fixture_path, .{ .iterate = true });
        defer fixture_dir.close();

        var walker = try fixture_dir.walk(testing.allocator);
        defer walker.deinit();

        var source_files: usize = 0;
        while (try walker.next()) |entry| {
            if (entry.kind == .file) {
                const ext = std.fs.path.extension(entry.path);
                if (std.mem.eql(u8, case.language, "Zig") and std.mem.eql(u8, ext, ".zig")) {
                    source_files += 1;
                } else if (std.mem.eql(u8, case.language, "Ts") and std.mem.eql(u8, ext, ".ts")) {
                    source_files += 1;
                }
            }
        }

        try testing.expect(source_files > 0);
        std.debug.print("✓ Found {d} source files for {s}\n", .{ source_files, case.language });
    }
}

test "table-driven fixture validation" {
    for (fixture_cases) |case| {
        std.debug.print("Testing {s} fixture...\n", .{case.language});

        // Validate fixture path exists
        var dir = std.fs.cwd().openDir(case.fixture_path, .{}) catch |err| {
            std.debug.print("Cannot open {s}: {}\n", .{ case.fixture_path, err });
            return err;
        };
        defer dir.close();

        // Validate golden files exist and have content
        const json_content = try std.fs.cwd().readFileAlloc(testing.allocator, case.golden_json, 1024 * 1024);
        defer testing.allocator.free(json_content);
        try testing.expect(json_content.len > 0);

        const mmd_content = try std.fs.cwd().readFileAlloc(testing.allocator, case.golden_mmd, 1024 * 1024);
        defer testing.allocator.free(mmd_content);
        try testing.expect(mmd_content.len > 0);

        std.debug.print("✓ {s} fixture validation complete\n", .{case.language});
    }
}
