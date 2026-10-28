const std = @import("std");
const plugin_loader = @import("plugin_loader");

// Default to enabled - matches plugin_loader
const no_plugins = plugin_loader.plugins_disabled;

// Stub implementation types and functions
const StubPluginHarness = struct {
    allocator: std.mem.Allocator,

    pub const TestResult = struct {
        plugin_id: []const u8,
        test_name: []const u8,
        passed: bool,
        error_message: ?[]const u8,
        duration_ns: u64,
    };

    pub fn init(allocator: std.mem.Allocator) !StubPluginHarness {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *StubPluginHarness) void {
        _ = self;
    }

    pub fn loadPlugin(self: *StubPluginHarness, plugin_path: []const u8) !void {
        _ = self;
        _ = plugin_path;
        return error.PluginsDisabled;
    }

    pub fn runBasicTests(self: *StubPluginHarness) !void {
        _ = self;
        return error.PluginsDisabled;
    }

    pub fn printResults(self: StubPluginHarness) void {
        _ = self;
    }

    pub fn hasFailures(self: StubPluginHarness) bool {
        _ = self;
        return false;
    }

    pub fn exportResultsJson(self: StubPluginHarness, writer: anytype) !void {
        _ = self;
        _ = writer;
        return;
    }
};

fn stubRunHarness(plugin_path: []const u8) !void {
    _ = plugin_path;
    return error.PluginsDisabled;
}

fn stubRunPluginTests(allocator: std.mem.Allocator) !void {
    _ = allocator;
    return error.PluginsDisabled;
}

// Select implementation based on compilation flag
pub const PluginHarness = if (no_plugins) StubPluginHarness else @import("plugin_harness_native.zig").PluginHarness;

pub fn runPluginTests(allocator: std.mem.Allocator) !void {
    if (no_plugins) {
        return stubRunPluginTests(allocator);
    } else {
        const native = @import("plugin_harness_native.zig");
        return native.runPluginTests(allocator);
    }
}
