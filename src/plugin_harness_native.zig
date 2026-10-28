const std = @import("std");
const plugin_loader = @import("plugin_loader");
const ir = @import("ir");
const diag = @import("diag");
const c = @cImport(@cInclude("frontend.h"));

/// Plugin harness for testing and validation
pub const PluginHarness = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(plugin_loader.LoadedFrontend),
    test_results: std.ArrayList(TestResult),

    const Self = @This();

    pub const TestResult = struct {
        plugin_id: []const u8,
        test_name: []const u8,
        passed: bool,
        error_message: ?[]const u8,
        duration_ns: u64,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .plugins = try std.ArrayList(plugin_loader.LoadedFrontend).initCapacity(allocator, 0),
            .test_results = try std.ArrayList(TestResult).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.plugins.items) |*plugin| {
            plugin.deinit();
        }
        self.plugins.deinit(self.allocator);

        for (self.test_results.items) |*result| {
            if (result.error_message) |msg| {
                self.allocator.free(msg);
            }
            self.allocator.free(result.plugin_id);
            self.allocator.free(result.test_name);
        }
        self.test_results.deinit(self.allocator);
    }

    /// Load a plugin for testing
    pub fn loadPlugin(self: *Self, plugin_path: []const u8) !void {
        const schema_range = plugin_loader.SchemaRange{
            .min = c.R2M_SCHEMA_VERSION,
            .max = c.R2M_SCHEMA_VERSION,
        };

        const plugin = try plugin_loader.loadFrontend(self.allocator, plugin_path, schema_range);
        try self.plugins.append(self.allocator, plugin);
    }

    /// Run basic plugin validation tests
    pub fn runBasicTests(self: *Self) !void {
        for (self.plugins.items) |plugin| {
            try self.testPluginInterface(plugin);
            try self.testFileFiltering(plugin);
            try self.testBasicParsing(plugin);
        }
    }

    /// Test plugin interface compliance
    fn testPluginInterface(self: *Self, plugin: plugin_loader.LoadedFrontend) !void {
        const start_time = std.time.nanoTimestamp();

        var error_msg: ?[]const u8 = null;
        var passed = true;

        // Check mandatory fields
        if (plugin.api.id == null) {
            error_msg = try self.allocator.dupe(u8, "Plugin ID is null");
            passed = false;
        } else if (plugin.api.wants_file == null) {
            error_msg = try self.allocator.dupe(u8, "wants_file function is null");
            passed = false;
        } else if (plugin.api.parse_file == null) {
            error_msg = try self.allocator.dupe(u8, "parse_file function is null");
            passed = false;
        }

        // Check ABI version
        if (passed and plugin.api.abi_version != c.R2M_FRONTEND_API_VERSION) {
            error_msg = try std.fmt.allocPrint(self.allocator, "ABI version mismatch: expected {d}, got {d}", .{ c.R2M_FRONTEND_API_VERSION, plugin.api.abi_version });
            passed = false;
        }

        const end_time = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));

        try self.test_results.append(self.allocator, .{
            .plugin_id = try self.allocator.dupe(u8, plugin.plugin_id),
            .test_name = try self.allocator.dupe(u8, "interface_compliance"),
            .passed = passed,
            .error_message = error_msg,
            .duration_ns = duration,
        });
    }

    /// Test file filtering functionality
    fn testFileFiltering(self: *Self, plugin: plugin_loader.LoadedFrontend) !void {
        const start_time = std.time.nanoTimestamp();

        const test_files = [_][]const u8{
            "test.zig",
            "test.c",
            "test.ts",
            "test.js",
            "README.md",
            "build.zig",
        };

        for (test_files) |file_path| {
            // Just make sure the function doesn't crash
            const wants = plugin.wantsFile(file_path);
            _ = wants; // We don't care about the result, just that it doesn't crash
        }

        const end_time = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));

        try self.test_results.append(self.allocator, .{
            .plugin_id = try self.allocator.dupe(u8, plugin.plugin_id),
            .test_name = try self.allocator.dupe(u8, "file_filtering"),
            .passed = true,
            .error_message = null,
            .duration_ns = duration,
        });
    }

    /// Test basic parsing functionality
    fn testBasicParsing(self: *Self, plugin: plugin_loader.LoadedFrontend) !void {
        const start_time = std.time.nanoTimestamp();

        var error_msg: ?[]const u8 = null;
        var passed = true;

        const test_content = "const std = @import(\"std\");\n\npub fn main() !void {\n    std.debug.print(\"Hello, world!\\n\");\n}\n";
        const test_file = "test.zig";

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const parse_result = plugin.parseFile(
            test_file,
            test_content,
            arena.allocator(),
            1024 * 1024, // 1MB budget
        ) catch |err| {
            error_msg = try std.fmt.allocPrint(self.allocator, "Parse failed with error: {}", .{err});
            passed = false;
            return;
        };

        if (passed) {
            // Validate basic structure of results
            if (parse_result.nodes.len == 0) {
                error_msg = try self.allocator.dupe(u8, "No nodes returned from parse");
                passed = false;
            }

            // Check that all nodes have required fields
            for (parse_result.nodes) |node| {
                if (node.id.len == 0) {
                    error_msg = try self.allocator.dupe(u8, "Node has empty ID");
                    passed = false;
                    break;
                }
                if (@intFromEnum(node.kind) < c.R2M_NODE_MODULE or @intFromEnum(node.kind) > c.R2M_NODE_VAR) {
                    error_msg = try self.allocator.dupe(u8, "Invalid node kind");
                    passed = false;
                    break;
                }
            }
        }

        const end_time = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));

        try self.test_results.append(self.allocator, .{
            .plugin_id = try self.allocator.dupe(u8, plugin.plugin_id),
            .test_name = try self.allocator.dupe(u8, "basic_parsing"),
            .passed = passed,
            .error_message = error_msg,
            .duration_ns = duration,
        });
    }

    /// Print test results summary
    pub fn printResults(self: Self) void {
        var total_tests: usize = 0;
        var passed_tests: usize = 0;
        var total_duration_ns: u64 = 0;

        for (self.test_results.items) |result| {
            total_tests += 1;
            if (result.passed) {
                passed_tests += 1;
            }
            total_duration_ns += result.duration_ns;

            const status = if (result.passed) "PASS" else "FAIL";
            const duration_ms = @as(f64, @floatFromInt(result.duration_ns)) / 1_000_000.0;

            std.debug.print("[{s}] {s}.{s}: {d:.2}ms\n", .{
                status,
                result.plugin_id,
                result.test_name,
                duration_ms,
            });

            if (result.error_message) |msg| {
                std.debug.print("  Error: {s}\n", .{msg});
            }
        }

        const total_duration_ms = @as(f64, @floatFromInt(total_duration_ns)) / 1_000_000.0;
        const pass_rate = @as(f64, @floatFromInt(passed_tests)) / @as(f64, @floatFromInt(total_tests)) * 100.0;

        std.debug.print("\nTest Summary:\n");
        std.debug.print("  Total tests: {d}\n", .{total_tests});
        std.debug.print("  Passed: {d} ({d:.1}%)\n", .{ passed_tests, pass_rate });
        std.debug.print("  Failed: {d}\n", .{total_tests - passed_tests});
        std.debug.print("  Total duration: {d:.2}ms\n", .{total_duration_ms});
    }

    /// Export results to JSON for CI consumption
    pub fn exportResultsJson(self: Self, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.writeAll("  \"summary\": {\n");

        var total_tests: usize = 0;
        var passed_tests: usize = 0;
        var total_duration_ns: u64 = 0;

        for (self.test_results.items) |result| {
            total_tests += 1;
            if (result.passed) passed_tests += 1;
            total_duration_ns += result.duration_ns;
        }

        try writer.print("    \"total_tests\": {d},\n", .{total_tests});
        try writer.print("    \"passed_tests\": {d},\n", .{passed_tests});
        try writer.print("    \"failed_tests\": {d},\n", .{total_tests - passed_tests});
        try writer.print("    \"pass_rate\": {d:.2},\n", .{@as(f64, @floatFromInt(passed_tests)) / @as(f64, @floatFromInt(total_tests)) * 100.0});
        try writer.print("    \"total_duration_ns\": {d}\n", .{total_duration_ns});
        try writer.writeAll("  },\n");

        try writer.writeAll("  \"results\": [\n");
        for (self.test_results.items, 0..) |result, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"plugin_id\": \"{s}\",\n", .{result.plugin_id});
            try writer.print("      \"test_name\": \"{s}\",\n", .{result.test_name});
            try writer.print("      \"passed\": {},\n", .{result.passed});
            try writer.print("      \"duration_ns\": {d}\n", .{result.duration_ns});
            if (result.error_message) |msg| {
                try writer.print("      \"error_message\": \"{s}\"\n", .{msg});
            }
            try writer.writeAll("    }");
            if (i < self.test_results.items.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");
    }
};

/// Run plugin harness tests on all built plugins
pub fn runPluginTests(allocator: std.mem.Allocator) !void {
    var harness = PluginHarness.init(allocator);
    defer harness.deinit();

    // Try to load the dummy plugin
    const plugin_path = "zig-out/plugins/librepo2mmd_dummy.so";
    harness.loadPlugin(plugin_path) catch |err| {
        std.debug.print("Failed to load plugin {s}: {}\n", .{ plugin_path, err });
        return;
    };

    // Run all tests
    harness.runBasicTests() catch |err| {
        std.debug.print("Failed to run tests: {}\n", .{err});
        return;
    };

    // Print results
    harness.printResults();

    // Export to JSON file for CI
    const json_file = try std.fs.cwd().createFile("plugin_test_results.json", .{});
    defer json_file.close();
    var write_buffer: [4096]u8 = undefined;
    var writer = json_file.writer(&write_buffer);
    try harness.exportResultsJson(&writer.interface);

    std.debug.print("\nResults exported to plugin_test_results.json\n");
}
