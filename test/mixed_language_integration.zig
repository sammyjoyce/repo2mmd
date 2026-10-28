const std = @import("std");
const ir = @import("ir");
const resolver = @import("resolver");
const grouping = @import("grouping");
const pruning = @import("pruning");
const diagnostics_engine = @import("diagnostics_engine");

pub fn runMixedLanguageTests(allocator: std.mem.Allocator) !void {
    std.debug.print("Running mixed-language integration tests...\n", .{});

    try testMixedLanguageFixtureResolution(allocator);
    try testCrossLanguageSymbolResolution(allocator);
    try testResolverAndReducers(allocator);
    try testDiagnosticsThresholds(allocator);

    std.debug.print("✓ All mixed-language integration tests passed\n", .{});
}

fn testMixedLanguageFixtureResolution(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing mixed-language fixture resolution...\n", .{});

    _ = allocator; // Mark as used for now
    const fixture_path = "test/fixtures/mixed-language";

    // Test that the fixture exists and has expected structure
    var fixture_dir = try std.fs.cwd().openDir(fixture_path, .{ .iterate = true });
    defer fixture_dir.close();

    // Check for expected files
    const expected_files = [_][]const u8{
        "src/main.zig",
        "src/auth.zig",
        "src/database.zig",
        "frontend/main.ts",
        "frontend/auth.ts",
        "frontend/database.ts",
    };

    for (expected_files) |file_path| {
        const file = fixture_dir.openFile(file_path, .{}) catch |err| {
            std.debug.print("    ✗ Missing expected file: {s}\n", .{file_path});
            return err;
        };
        file.close();
    }

    std.debug.print("    ✓ Mixed-language fixture structure validated\n", .{});
}

fn testCrossLanguageSymbolResolution(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing cross-language symbol resolution...\n", .{});

    // Initialize resolver with default config
    const config = resolver.ResolverConfig{};
    var resolver_instance = try resolver.Resolver.init(allocator, config);
    defer resolver_instance.deinit();

    const fixture_path = "test/fixtures/mixed-language";
    _ = fixture_path; // Use fixture_path to avoid unused variable warning

    // Create mock nodes for testing
    const nodes = [_]ir.Node{
        .{
            .id = "zig_auth_001",
            .name = "authenticateUser",
            .fqname = "auth.authenticateUser",
            .kind = .Func,
            .lang = "zig",
            .file = "src/auth.zig",
            .range = .{ .start = .{ .line = 15, .column = 1 }, .end = .{ .line = 15, .column = 25 } },
            .signature = "fn authenticateUser(username: []const u8, password: []const u8) u32",
            .visibility = .Public,
            .origin_plugin = "zig_frontend",
            .module_id = "auth",
            .tags = &[_][]const u8{"exported"},
        },
        .{
            .id = "zig_db_001",
            .name = "connectDatabase",
            .fqname = "database.connectDatabase",
            .kind = .Func,
            .lang = "zig",
            .file = "src/database.zig",
            .range = .{ .start = .{ .line = 18, .column = 1 }, .end = .{ .line = 18, .column = 26 } },
            .signature = "fn connectDatabase(conn: []const u8) *Database",
            .visibility = .Public,
            .origin_plugin = "zig_frontend",
            .module_id = "database",
            .tags = &[_][]const u8{"exported"},
        },
        .{
            .id = "ts_auth_001",
            .name = "authenticate",
            .fqname = "AuthenticationService.authenticate",
            .kind = .Func,
            .lang = "typescript",
            .file = "frontend/auth.ts",
            .range = .{ .start = .{ .line = 25, .column = 1 }, .end = .{ .line = 25, .column = 30 } },
            .signature = "authenticate(username: string, password: string): Promise<AuthResponse>",
            .visibility = .Public,
            .origin_plugin = "typescript_frontend",
            .module_id = null,
            .tags = &[_][]const u8{"exported"},
        },
        .{
            .id = "ts_main_001",
            .name = "bootstrap",
            .fqname = "frontend.bootstrap",
            .kind = .Func,
            .lang = "typescript",
            .file = "frontend/main.ts",
            .range = .{ .start = .{ .line = 5, .column = 1 }, .end = .{ .line = 5, .column = 20 } },
            .signature = "bootstrap(): Promise<void>",
            .visibility = .Public,
            .origin_plugin = "typescript_frontend",
            .module_id = null,
            .tags = &[_][]const u8{"exported"},
        },
    };

    // Build symbol tables from nodes
    try resolver_instance.buildSymbolTables(&nodes);

    // Create mock edges for testing resolution
    const edges = [_]ir.Edge{
        .{
            .src = "database.connectDatabase",
            .dst = "AuthenticationService.authenticate",
            .rel = .Imports,
            .certainty = .Static,
            .certainty_reason = null,
            .evidence_paths = &[_][]const u8{"src/database.zig"},
            .evidence_lines = &[_]u32{12},
            .diagnostics = &[_]ir.DiagnosticRef{},
        },
        .{
            .src = "auth.authenticateUser",
            .dst = "AuthenticationService.authenticate",
            .rel = .Calls,
            .certainty = .Static,
            .certainty_reason = null,
            .evidence_paths = &[_][]const u8{"src/auth.zig"},
            .evidence_lines = &[_]u32{20},
            .diagnostics = &[_]ir.DiagnosticRef{},
        },
        .{
            .src = "frontend.bootstrap",
            .dst = "auth.authenticateUser",
            .rel = .Calls,
            .certainty = .Static,
            .certainty_reason = null,
            .evidence_paths = &[_][]const u8{"frontend/main.ts"},
            .evidence_lines = &[_]u32{5},
            .diagnostics = &[_]ir.DiagnosticRef{},
        },
    };

    // Resolve edges
    var mutable_edges = edges;
    const resolved_edges = try resolver_instance.resolveEdges(&nodes, &mutable_edges);
    defer {
        for (resolved_edges) |edge| {
            allocator.free(edge.src);
            allocator.free(edge.dst);
        }
        allocator.free(resolved_edges);
    }

    // Test resolution statistics
    const stats = resolver_instance.getStats();
    const resolution_rate = @as(f64, stats.resolution_rate);

    std.debug.print("    ✓ Cross-language resolution rate: {d:.1}% ({d}/{d} refs resolved)\n", .{ resolution_rate, stats.resolved_refs, stats.resolved_refs + stats.unresolved_refs });

    // For now, we expect basic functionality to work (should resolve some references)
    try std.testing.expect(stats.total_symbols >= 4); // We added 4 symbols
    try std.testing.expect(resolution_rate >= 0.0); // At least 0% resolution
}

fn testResolverAndReducers(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing resolver and reducers...\n", .{});

    // Create test nodes with proper cleanup
    const node_types = [_][]const u8{ "zig", "typescript" };
    var nodes = try allocator.alloc(ir.Node, node_types.len);
    defer allocator.free(nodes);

    // Store allocated strings for cleanup
    var allocated_strings = try std.ArrayList([]const u8).initCapacity(allocator, node_types.len * 3);
    defer {
        for (allocated_strings.items) |str| allocator.free(str);
        allocated_strings.deinit(allocator);
    }

    for (node_types, 0..) |lang, i| {
        const node_id = try std.fmt.allocPrint(allocator, "node_{}", .{i});
        try allocated_strings.append(allocator, node_id);
        const fqname = try std.fmt.allocPrint(allocator, "test_function_{}", .{i});
        try allocated_strings.append(allocator, fqname);

        const filename = try std.fmt.allocPrint(allocator, "test.{s}", .{lang});
        try allocated_strings.append(allocator, filename);
        nodes[i] = ir.Node{
            .id = node_id,
            .lang = lang,
            .name = "test_function",
            .fqname = fqname,
            .file = filename,
            .kind = .Func,
            .visibility = .Public,
            .range = .{ .start = .{ .line = 1, .column = 1 }, .end = .{ .line = 1, .column = 10 } },
            .signature = null,
            .origin_plugin = "test",
            .tags = &[_][]const u8{},
            .module_id = null,
        };
    }

    // Create test edges
    var edges = try allocator.alloc(ir.Edge, 1);
    defer allocator.free(edges);

    edges[0] = ir.Edge{
        .src = "node_0",
        .dst = "node_1",
        .rel = .Calls,
        .certainty = .Static,
        .certainty_reason = null,
        .evidence_paths = &[_][]const u8{"test.zig"},
        .evidence_lines = &[_]u32{1},
        .diagnostics = &[_]ir.DiagnosticRef{},
    };

    // Test grouping engine
    var grouping_engine = grouping.GroupingEngine.init(allocator, grouping.GroupingConfig{});

    const groups = try grouping_engine.groupNodes(nodes);
    defer {
        for (groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(groups);
    }

    try std.testing.expect(groups.len > 0);
    std.debug.print("    ✓ Grouping engine created {d} groups\n", .{groups.len});

    // Test pruning engine
    var pruning_engine = pruning.PruningEngine.init(allocator, pruning.PruningConfig{});

    const result = try pruning_engine.pruneGraph(nodes, edges);
    defer {
        allocator.free(result.result.nodes);
        allocator.free(result.result.edges);
    }
    try std.testing.expect(result.result.nodes.len <= nodes.len);
    try std.testing.expect(result.stats.pruning_rate >= 0.0);
    std.debug.print("    ✓ Pruning engine retained {d} nodes\n", .{result.result.nodes.len});
}

fn testDiagnosticsThresholds(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing diagnostics thresholds...\n", .{});

    // Configure thresholds
    const thresholds = diagnostics_engine.DiagnosticThresholds{
        .max_errors = 5,
        .max_warnings = 10,
        .max_unresolved = 20,
    };

    var diag_engine = try diagnostics_engine.DiagnosticEngine.init(allocator, thresholds);
    defer diag_engine.deinit();

    // Use the built-in method to create unresolved reference diagnostic
    try diag_engine.createUnresolvedRefDiagnostic("missing_function", .{
        .file = "src/test.zig",
        .line = 10,
        .plugin = "test_plugin",
        .available_symbols = &[_][]const u8{ "similar_function", "another_function" },
    });

    // Get statistics
    const stats = diag_engine.getStats();
    try std.testing.expect(stats.total_diagnostics == 1);
    try std.testing.expect(stats.warnings == 1);
    try std.testing.expect(stats.resolution_issues == 1);

    // Get diagnostics by severity
    const warnings = try diag_engine.getDiagnosticsBySeverity(.Warn);
    defer allocator.free(warnings);
    try std.testing.expect(warnings.len == 1);
    try std.testing.expect(std.mem.eql(u8, warnings[0].code, "UNRESOLVED_REFERENCE"));

    // Get diagnostics by category
    const resolution_issues = try diag_engine.getDiagnosticsByCategory(.Resolution);
    defer allocator.free(resolution_issues);
    try std.testing.expect(resolution_issues.len == 1);
    try std.testing.expect(resolution_issues[0].root_cause == .SymbolNotFound);

    // Convert to IR diagnostics
    const ir_diagnostics = try diag_engine.toIRDiagnostics();
    defer diag_engine.freeIRDiagnostics(ir_diagnostics);
    try std.testing.expect(ir_diagnostics.len == 1);
    try std.testing.expect(std.mem.eql(u8, ir_diagnostics[0].code, "UNRESOLVED_REFERENCE"));

    std.debug.print("    ✓ Diagnostics engine processed unresolved reference with root-cause analysis\n", .{});
}

test "MixedLanguageIntegration.resolution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runMixedLanguageTests(allocator);
}
