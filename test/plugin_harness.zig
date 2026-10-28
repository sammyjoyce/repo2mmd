const std = @import("std");
const testing = std.testing;
const plugin_loader = @import("../src/plugin_loader.zig");
const ir = @import("../src/ir.zig");
const c = @cImport(@cInclude("frontend.h"));

/// Test fixture for plugin validation
pub const Fixture = struct {
    file_path: []const u8,
    content: []const u8,
    expected_nodes: usize,
    expected_edges: usize,
    expected_success: bool = true,
};

/// Result from running a plugin test
pub const HarnessResult = struct {
    success: bool,
    node_count: usize,
    edge_count: usize,
    diagnostic_count: usize,
    error_message: ?[]const u8 = null,
};

/// Run a plugin against a set of test fixtures
pub fn runPluginFixture(
    allocator: std.mem.Allocator,
    plugin_path: []const u8,
    fixtures: []const Fixture,
) !HarnessResult {
    const schema_range = plugin_loader.SchemaRange{
        .min = c.R2M_SCHEMA_VERSION,
        .max = c.R2M_SCHEMA_VERSION,
    };

    var frontend = try plugin_loader.loadFrontend(allocator, plugin_path, schema_range);
    defer frontend.deinit();

    var total_nodes: usize = 0;
    var total_edges: usize = 0;
    var total_diagnostics: usize = 0;

    for (fixtures) |fixture| {
        // Test wants_file first
        if (!frontend.wantsFile(fixture.file_path)) {
            continue;
        }

        // Create an arena for this parse
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        // Parse the file
        const result = try frontend.parseFile(
            fixture.file_path,
            fixture.content,
            arena.allocator(),
            1024 * 1024, // 1MB max
        );

        total_nodes += result.nodes.len;
        total_edges += result.edges.len;
        total_diagnostics += result.diagnostics.len;

        // Validate expectations
        if (result.success != fixture.expected_success) {
            return HarnessResult{
                .success = false,
                .node_count = total_nodes,
                .edge_count = total_edges,
                .diagnostic_count = total_diagnostics,
                .error_message = try allocator.dupe(u8, "Parse success mismatch"),
            };
        }

        if (result.nodes.len != fixture.expected_nodes) {
            return HarnessResult{
                .success = false,
                .node_count = total_nodes,
                .edge_count = total_edges,
                .diagnostic_count = total_diagnostics,
                .error_message = try std.fmt.allocPrint(allocator, "Node count mismatch: expected {d}, got {d}", .{ fixture.expected_nodes, result.nodes.len }),
            };
        }

        if (result.edges.len != fixture.expected_edges) {
            return HarnessResult{
                .success = false,
                .node_count = total_nodes,
                .edge_count = total_edges,
                .diagnostic_count = total_diagnostics,
                .error_message = try std.fmt.allocPrint(allocator, "Edge count mismatch: expected {d}, got {d}", .{ fixture.expected_edges, result.edges.len }),
            };
        }
    }

    return HarnessResult{
        .success = true,
        .node_count = total_nodes,
        .edge_count = total_edges,
        .diagnostic_count = total_diagnostics,
    };
}

/// Test plugin loading with invalid inputs
pub fn testPluginLoadingErrors(allocator: std.mem.Allocator) !void {
    // Test loading non-existent plugin
    const schema_range = plugin_loader.SchemaRange{
        .min = c.R2M_SCHEMA_VERSION,
        .max = c.R2M_SCHEMA_VERSION,
    };

    const load_result = plugin_loader.loadFrontend(allocator, "nonexistent.so", schema_range);
    try testing.expectError(error.PluginNotFound, load_result);

    // TODO: Add more error cases when we have test plugins available
    // - Invalid plugin (missing symbols)
    // - Version mismatch
    // - Schema incompatibility
}

test "plugin_harness_basic_functionality" {
    const allocator = testing.allocator;

    // Test error handling first
    try testPluginLoadingErrors(allocator);

    // TODO: Test with actual dummy plugin when available
    // const dummy_plugin_path = "zig-out/plugins/librepo2mmd_dummy.so";
    // const fixtures = [_]Fixture{
    //     .{
    //         .file_path = "test.zig",
    //         .content = "const std = @import(\"std\");",
    //         .expected_nodes = 1,
    //         .expected_edges = 0,
    //     },
    // };

    // const result = try runPluginFixture(allocator, dummy_plugin_path, &fixtures);
    // try testing.expect(result.success);
    // try testing.expectEqual(@as(usize, 1), result.node_count);
    // try testing.expectEqual(@as(usize, 0), result.edge_count);
}

test "plugin_lifecycle_management" {
    const allocator = testing.allocator;

    // TODO: Test with actual plugin
    // Load plugin
    // Use plugin
    // Ensure cleanup happens correctly
    _ = allocator;
}

/// Integration test with existing fixtures
pub fn testWithExistingFixtures(allocator: std.mem.Allocator, plugin_path: []const u8) !void {
    // Load fixtures from test/fixtures directory
    var fixtures = try std.ArrayList(Fixture).initCapacity(allocator, 0);
    defer fixtures.deinit(allocator);

    // Add Zig fixture
    try fixtures.append(Fixture{
        .file_path = "test/fixtures/zig/main.zig",
        .content = @embedFile("../test/fixtures/zig/main.zig"),
        .expected_nodes = 1, // Dummy plugin should create one node per file
        .expected_edges = 0,
    });

    // Add TypeScript fixture
    try fixtures.append(Fixture{
        .file_path = "test/fixtures/typescript/index.ts",
        .content = @embedFile("../test/fixtures/typescript/index.ts"),
        .expected_nodes = 1,
        .expected_edges = 0,
    });

    const result = try runPluginFixture(allocator, plugin_path, fixtures.items);

    // All fixtures should be processed by dummy plugin
    try testing.expect(result.success);
    try testing.expectEqual(@as(usize, 2), result.node_count); // One node per file
    try testing.expectEqual(@as(usize, 0), result.edge_count);
}
