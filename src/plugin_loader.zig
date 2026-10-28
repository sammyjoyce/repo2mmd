const std = @import("std");
const ir = @import("ir");

// Default to enabled - the build system can override this with proper conditional compilation
const no_plugins = false;

pub const plugins_disabled = no_plugins;

// Stub implementation types and functions
const StubHostServices = struct {
    allocator: std.mem.Allocator,

    pub fn createHostTable(self: *@This()) void {
        _ = self;
    }
};

const StubSchemaRange = struct {
    min: u32,
    max: u32,
};

const StubApi = struct {
    abi_version: u32 = 0,
};

const StubLoadedFrontend = struct {
    allocator: std.mem.Allocator,
    plugin_id: []const u8,
    host_services: StubHostServices,
    api: *const StubApi = &default_api,

    const default_api = StubApi{};

    pub fn deinit(self: *StubLoadedFrontend) void {
        _ = self;
    }

    pub fn wantsFile(self: StubLoadedFrontend, path: []const u8) bool {
        _ = self;
        _ = path;
        return false;
    }

    pub fn parseFile(
        self: StubLoadedFrontend,
        file_path: []const u8,
        content: []const u8,
        arena: std.mem.Allocator,
        max_bytes: u32,
    ) !StubParseResult {
        _ = self;
        _ = file_path;
        _ = content;
        _ = arena;
        _ = max_bytes;

        return error.PluginsDisabled;
    }

    pub fn postResolve(self: StubLoadedFrontend, graph: *ir.Graph) !void {
        _ = self;
        _ = graph;
        return;
    }
};

const StubParseResult = struct {
    nodes: []ir.Node,
    edges: []ir.Edge,
    diagnostics: []ir.Diagnostic,
    success: bool,
};

const StubLoadError = error{
    PluginsDisabled,
};

fn stubLoadFrontend(
    allocator: std.mem.Allocator,
    path: []const u8,
    expected_schema: StubSchemaRange,
) !StubLoadedFrontend {
    _ = allocator;
    _ = path;
    _ = expected_schema;

    return error.PluginsDisabled;
}

fn stubTestPluginLoad(plugin_path: []const u8) !void {
    _ = plugin_path;
    return error.PluginsDisabled;
}

// Select implementation based on compilation flag
pub const HostServices = if (no_plugins) StubHostServices else @import("plugin_loader_native.zig").HostServices;
pub const SchemaRange = if (no_plugins) StubSchemaRange else @import("plugin_loader_native.zig").SchemaRange;
pub const LoadedFrontend = if (no_plugins) StubLoadedFrontend else @import("plugin_loader_native.zig").LoadedFrontend;
pub const ParseResult = if (no_plugins) StubParseResult else @import("plugin_loader_native.zig").ParseResult;
pub const LoadError = if (no_plugins) StubLoadError else @import("plugin_loader_native.zig").LoadError;

pub fn loadFrontend(
    allocator: std.mem.Allocator,
    path: []const u8,
    expected_schema: SchemaRange,
) !LoadedFrontend {
    if (no_plugins) {
        return stubLoadFrontend(allocator, path, expected_schema);
    } else {
        const native = @import("plugin_loader_native.zig");
        return native.loadFrontend(allocator, path, expected_schema);
    }
}

pub fn testPluginLoad(plugin_path: []const u8) !void {
    if (no_plugins) {
        return stubTestPluginLoad(plugin_path);
    } else {
        const native = @import("plugin_loader_native.zig");
        return native.testPluginLoad(plugin_path);
    }
}
