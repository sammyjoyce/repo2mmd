const std = @import("std");
const ir = @import("ir");
const diag = @import("diag");
const c = @cImport(@cInclude("frontend.h"));

/// Host service implementation for plugins
pub const HostServices = struct {
    allocator: std.mem.Allocator,
    plugin_id: []const u8 = "",
    plugin_abi_version: []const u8 = "",
    plugin_semver: []const u8 = "",

    fn logCallback(state: ?*anyopaque, severity: c.r2m_severity_t, message: [*c]const u8) callconv(.c) void {
        _ = @as(?*HostServices, @ptrCast(@alignCast(state))) orelse return;
        const msg = std.mem.span(message);

        // Plugin info logs are trace output; only warnings and errors reach the user.
        const level = switch (severity) {
            c.R2M_SEV_WARN => diag.Severity.Ok,
            c.R2M_SEV_ERROR => diag.Severity.Error,
            else => return,
        };

        diag.print(level, "plugin: {s}", .{msg}) catch {};
    }

    fn readFileCallback(state: ?*anyopaque, path: [*c]const c.r2m_path_view_t, content: [*c]c.r2m_path_view_t) callconv(.c) bool {
        const host = @as(?*HostServices, @ptrCast(@alignCast(state))) orelse return false;
        const path_slice = path.*.data[0..path.*.len];

        // Try to open the file - first as absolute path, then relative to project root
        const file = if (std.fs.path.isAbsolute(path_slice))
            std.fs.openFileAbsolute(path_slice, .{}) catch return false
        else
            std.fs.cwd().openFile(path_slice, .{}) catch return false;
        defer file.close();

        const contents = file.readToEndAlloc(host.allocator, 1024 * 1024) catch return false;
        content.*.data = contents.ptr;
        content.*.len = contents.len;
        return true;
    }

    fn freeContentCallback(state: ?*anyopaque, content: [*c]c.r2m_path_view_t) callconv(.c) void {
        const host = @as(?*HostServices, @ptrCast(@alignCast(state))) orelse return;
        if (content.*.len > 0) {
            host.allocator.free(content.*.data[0..content.*.len]);
        }
        content.* = std.mem.zeroes(c.r2m_path_view_t);
    }

    fn cacheGetCallback(state: ?*anyopaque, path: [*c]const c.r2m_path_view_t, data: [*c]?*const anyopaque, size: [*c]usize) callconv(.c) bool {
        const host = @as(?*HostServices, @ptrCast(@alignCast(state))) orelse return false;
        const path_slice = path.*.data[0..path.*.len];

        // Simple file-based cache implementation
        var cache_dir = std.fs.cwd().openDir(".repo2mmd/cache", .{}) catch return false;
        defer cache_dir.close();

        const key_material = std.fmt.allocPrint(
            host.allocator,
            "{s}|{s}|{s}|{s}",
            .{ path_slice, host.plugin_id, host.plugin_abi_version, host.plugin_semver },
        ) catch return false;
        defer host.allocator.free(key_material);

        const cache_key = std.hash.Wyhash.hash(0, key_material);
        const cache_filename = std.fmt.allocPrint(host.allocator, "{x:0>16}.cache", .{cache_key}) catch return false;
        defer host.allocator.free(cache_filename);

        const cache_file = cache_dir.openFile(cache_filename, .{}) catch return false;
        defer cache_file.close();

        const contents = cache_file.readToEndAlloc(host.allocator, 1024 * 1024) catch return false;
        data.* = contents.ptr;
        size.* = contents.len;

        return true;
    }

    fn cachePutCallback(state: ?*anyopaque, path: [*c]const c.r2m_path_view_t, data: ?*const anyopaque, size: usize) callconv(.c) bool {
        const host = @as(?*HostServices, @ptrCast(@alignCast(state))) orelse return false;
        const path_slice = path.*.data[0..path.*.len];

        if (data == null or size == 0) return false;

        // Create cache directory if it doesn't exist
        std.fs.cwd().makePath(".repo2mmd/cache") catch return false;
        var cache_dir = std.fs.cwd().openDir(".repo2mmd/cache", .{}) catch return false;
        defer cache_dir.close();

        const key_material = std.fmt.allocPrint(
            host.allocator,
            "{s}|{s}|{s}|{s}",
            .{ path_slice, host.plugin_id, host.plugin_abi_version, host.plugin_semver },
        ) catch return false;
        defer host.allocator.free(key_material);

        const cache_key = std.hash.Wyhash.hash(0, key_material);
        const cache_filename = std.fmt.allocPrint(host.allocator, "{x:0>16}.cache", .{cache_key}) catch return false;
        defer host.allocator.free(cache_filename);

        const cache_file = cache_dir.createFile(cache_filename, .{}) catch return false;
        defer cache_file.close();

        const data_slice = @as([*]const u8, @ptrCast(data))[0..size];
        _ = cache_file.writeAll(data_slice) catch return false;

        return true;
    }

    pub fn createHostTable(self: *HostServices) c.r2m_frontend_host_v1_t {
        return .{
            .log = logCallback,
            .log_state = self,
            .read_file = readFileCallback,
            .free_content = freeContentCallback,
            .io_state = self,
            .cache_get = cacheGetCallback,
            .cache_put = cachePutCallback,
            .cache_state = self,
            .abi_version = c.R2M_FRONTEND_API_VERSION,
            .struct_size = @sizeOf(c.r2m_frontend_host_v1_t),
            .reserved = .{ null, null, null },
        };
    }
};

/// Schema version range for compatibility checking
pub const SchemaRange = struct {
    min: u32,
    max: u32,
};

/// Loaded plugin wrapper that manages lifetime
pub const LoadedFrontend = struct {
    lib: std.DynLib,
    api: *const c.r2m_frontend_v1_t,
    plugin_id: []const u8,
    plugin_abi_version: []const u8,
    plugin_semver: []const u8,
    schema_min: u32,
    schema_max: u32,
    owns_semver: bool,
    allocator: std.mem.Allocator,
    host_services: HostServices,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        if (self.api.teardown) |teardown_fn| {
            _ = teardown_fn();
        } else if (self.api.shutdown) |shutdown_fn| {
            _ = shutdown_fn();
        }
        self.lib.close();
        self.allocator.free(self.plugin_id);
        self.allocator.free(self.plugin_abi_version);
        if (self.owns_semver and self.plugin_semver.len > 0) {
            self.allocator.free(self.plugin_semver);
        }
    }

    pub fn wantsFile(self: Self, path: []const u8) bool {
        const path_view = c.r2m_path_view_t{
            .data = path.ptr,
            .len = path.len,
        };
        return self.api.wants_file.?(&path_view);
    }

    pub fn parseFile(
        self: Self,
        file_path: []const u8,
        content: []const u8,
        arena: std.mem.Allocator,
        max_bytes: u32,
    ) !ParseResult {
        // Note: Memory budgeting using max_bytes would require custom allocator implementation
        // For now, we rely on the arena allocator's natural limits

        const path_view = c.r2m_path_view_t{
            .data = file_path.ptr,
            .len = file_path.len,
        };
        const content_view = c.r2m_path_view_t{
            .data = content.ptr,
            .len = content.len,
        };

        // Create host services table
        var host_services = self.host_services;
        var host_table = host_services.createHostTable();

        // Create arena interface
        var arena_interface = c.r2m_arena_t{
            .state = @as(?*anyopaque, @ptrCast(@constCast(&arena))),
            .alloc = struct {
                fn alloc(state: ?*anyopaque, alignment: usize, size: usize) callconv(.c) ?*anyopaque {
                    if (size == 0) return null;
                    const alloc_state = @as(*std.mem.Allocator, @ptrCast(@alignCast(state))).*;
                    if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return null;
                    return alloc_state.rawAlloc(size, std.mem.Alignment.fromByteUnits(alignment), @returnAddress());
                }
            }.alloc,
            .reset = struct {
                fn reset(state: ?*anyopaque) callconv(.c) void {
                    // Arena reset is a no-op for Zig allocators
                    // The arena will be freed when the allocator is destroyed
                    _ = state;
                }
            }.reset,
            .max_bytes = max_bytes,
            .used_bytes = 0,
            .abi_version = c.R2M_FRONTEND_API_VERSION,
            .struct_size = @sizeOf(c.r2m_arena_t),
            .reserved = .{ null, null, null },
        };

        const request = c.r2m_parse_request_t{
            .file_path = path_view,
            .content = content_view,
            .project_root = std.mem.zeroes(c.r2m_path_view_t),
            .compilation_database = null,
            .cli_args = null,
            .cli_arg_count = 0,
            .arena = &arena_interface,
            .host = &host_table,
            .max_bytes = max_bytes,
            .diagnostic_budget = 100,
            .parse_flags = 0,
            .abi_version = c.R2M_FRONTEND_API_VERSION,
            .struct_size = @sizeOf(c.r2m_parse_request_t),
            .reserved = .{ null, null, null },
        };

        var response = c.r2m_parse_response_t{
            .nodes = null,
            .node_count = 0,
            .edges = null,
            .edge_count = 0,
            .diagnostics = null,
            .diagnostic_count = 0,
            .status = c.R2M_STATUS_FATAL,
            .error_message = null,
            .abi_version = c.R2M_FRONTEND_API_VERSION,
            .struct_size = @sizeOf(c.r2m_parse_response_t),
            .reserved = .{ null, null, null },
        };

        const status = self.api.parse_file.?(&request, &response);

        if (status != c.R2M_STATUS_OK) {
            const error_msg = if (response.error_message) |msg|
                std.mem.span(msg)
            else
                "Unknown plugin error";
            diag.printError("Plugin parse error: {s}", .{error_msg}) catch {};
            return error.PluginParseError;
        }

        // Convert C arrays to Zig slices with proper field conversion
        var nodes_list = try std.ArrayList(ir.Node).initCapacity(arena, response.node_count);

        if (response.nodes != null and response.node_count > 0) {
            const c_nodes = response.nodes[0..response.node_count];
            for (c_nodes) |c_node| {
                const node = ir.Node{
                    .id = try arena.dupe(u8, c_node.id.data[0..c_node.id.len]),
                    .lang = try arena.dupe(u8, c_node.lang.data[0..c_node.lang.len]),
                    .kind = @enumFromInt(c_node.kind),
                    .name = try arena.dupe(u8, c_node.name.data[0..c_node.name.len]),
                    .fqname = try arena.dupe(u8, c_node.fqname.data[0..c_node.fqname.len]),
                    .file = try arena.dupe(u8, c_node.file.data[0..c_node.file.len]),
                    .range = .{
                        .start = .{
                            .line = c_node.range.start.line,
                            .column = c_node.range.start.column,
                        },
                        .end = .{
                            .line = c_node.range.end.line,
                            .column = c_node.range.end.column,
                        },
                    },
                    .signature = if (c_node.signature.len > 0) try arena.dupe(u8, c_node.signature.data[0..c_node.signature.len]) else null,
                    .visibility = @enumFromInt(c_node.visibility),
                    .origin_plugin = try arena.dupe(u8, c_node.origin_plugin.data[0..c_node.origin_plugin.len]),
                    .module_id = if (c_node.module_id.len > 0) try arena.dupe(u8, c_node.module_id.data[0..c_node.module_id.len]) else null,
                    .tags = &[_][]const u8{}, // TODO: Convert tags array properly
                };
                try nodes_list.append(arena, node);
            }
        }

        var edges_list = try std.ArrayList(ir.Edge).initCapacity(arena, response.edge_count);
        defer edges_list.deinit(arena);

        if (response.edges != null and response.edge_count > 0) {
            const c_edges = response.edges[0..response.edge_count];
            for (c_edges) |c_edge| {
                // Evidence is (path, line) pairs; drop it if a plugin sends mismatched arrays.
                const evidence_count: usize = if (c_edge.evidence_paths != null and c_edge.evidence_lines != null and
                    c_edge.evidence_path_count == c_edge.evidence_line_count) c_edge.evidence_path_count else 0;
                const evidence_paths = try arena.alloc([]const u8, evidence_count);
                for (evidence_paths, 0..) |*path, i| {
                    const view = c_edge.evidence_paths[i];
                    path.* = try arena.dupe(u8, view.data[0..view.len]);
                }
                const evidence_lines: []const u32 = if (evidence_count > 0) try arena.dupe(u32, c_edge.evidence_lines[0..evidence_count]) else &.{};
                const edge = ir.Edge{
                    .src = try arena.dupe(u8, c_edge.src.data[0..c_edge.src.len]),
                    .dst = try arena.dupe(u8, c_edge.dst.data[0..c_edge.dst.len]),
                    .rel = @enumFromInt(c_edge.rel),
                    .certainty = @enumFromInt(c_edge.certainty),
                    .certainty_reason = if (c_edge.certainty_reason.len > 0) try arena.dupe(u8, c_edge.certainty_reason.data[0..c_edge.certainty_reason.len]) else null,
                    .evidence_paths = evidence_paths,
                    .evidence_lines = evidence_lines,
                    .diagnostics = &[_]ir.DiagnosticRef{}, // TODO: Convert diagnostics properly
                };
                try edges_list.append(arena, edge);
            }
        }

        var diagnostics_list = try std.ArrayList(ir.Diagnostic).initCapacity(arena, response.diagnostic_count);
        defer diagnostics_list.deinit(arena);

        if (response.diagnostics != null and response.diagnostic_count > 0) {
            const c_diagnostics = response.diagnostics[0..response.diagnostic_count];
            for (c_diagnostics) |c_diagnostic| {
                const diagnostic = ir.Diagnostic{
                    .id = try arena.dupe(u8, c_diagnostic.id.data[0..c_diagnostic.id.len]),
                    .severity = @enumFromInt(c_diagnostic.severity),
                    .message = try arena.dupe(u8, c_diagnostic.message.data[0..c_diagnostic.message.len]),
                    .file = if (c_diagnostic.file.len > 0) try arena.dupe(u8, c_diagnostic.file.data[0..c_diagnostic.file.len]) else "",
                    .range = .{
                        .start = .{
                            .line = c_diagnostic.range.start.line,
                            .column = c_diagnostic.range.start.column,
                        },
                        .end = .{
                            .line = c_diagnostic.range.end.line,
                            .column = c_diagnostic.range.end.column,
                        },
                    },
                    .tags = &[_][]const u8{}, // TODO: Convert tags properly
                };
                try diagnostics_list.append(arena, diagnostic);
            }
        }

        return ParseResult{
            .nodes = try nodes_list.toOwnedSlice(arena),
            .edges = try edges_list.toOwnedSlice(arena),
            .diagnostics = try diagnostics_list.toOwnedSlice(arena),
            .success = response.status == c.R2M_STATUS_OK,
        };
    }

    pub fn postResolve(self: Self, graph: *ir.Graph) !void {
        if (self.api.post_resolve) |post_resolve_fn| {
            std.debug.print("DEBUG: postResolve called for plugin {s} with {d} nodes, {d} edges\n", .{ self.plugin_id, graph.nodes.len, graph.edges.len });

            // Convert Zig graph to C representation
            const c_nodes = if (graph.nodes.len > 0)
                @as([*]c.r2m_node_t, @ptrCast(@constCast(graph.nodes.ptr)))
            else
                null;

            const c_edges = if (graph.edges.len > 0)
                @as([*]c.r2m_edge_t, @ptrCast(@constCast(graph.edges.ptr)))
            else
                null;

            const c_graph = c.r2m_graph_t{
                .nodes = c_nodes,
                .node_count = @intCast(graph.nodes.len),
                .edges = c_edges,
                .edge_count = @intCast(graph.edges.len),
            };

            std.debug.print("DEBUG: Calling C post_resolve function\n", .{});
            const result = post_resolve_fn(&c_graph);
            std.debug.print("DEBUG: C post_resolve returned with status: {d}\n", .{result});

            if (result != c.R2M_STATUS_OK) {
                return error.PostResolveFailed;
            }
        } else {
            std.debug.print("DEBUG: Plugin {s} does not have post_resolve function\n", .{self.plugin_id});
        }
    }
};

/// Result from parsing a file
pub const ParseResult = struct {
    nodes: []ir.Node,
    edges: []ir.Edge,
    diagnostics: []ir.Diagnostic,
    success: bool,
};

/// Load a frontend plugin from the given path
pub fn loadFrontend(
    allocator: std.mem.Allocator,
    path: []const u8,
    expected_schema: SchemaRange,
) !LoadedFrontend {
    // Resolve platform-specific library suffix if needed
    const lib_path = try resolveLibraryPath(allocator, path);
    defer allocator.free(lib_path);

    // Load the dynamic library
    var lib = std.DynLib.open(lib_path) catch |err| switch (err) {
        error.FileNotFound => return error.PluginNotFound,
        else => return error.UnableToLoadPlugin,
    };

    // Look up the entry point
    const get_frontend = lib.lookup(
        *const fn () *const c.r2m_frontend_v1_t,
        "r2m_get_frontend_v1",
    ) orelse {
        lib.close();
        return error.MissingEntryPoint;
    };

    // Get the plugin interface
    const api = get_frontend();

    // Log ABI negotiation
    const plugin_id_c = api.id orelse @as([*c]const u8, @ptrCast("unknown"));
    const plugin_id_slice = std.mem.span(plugin_id_c);
    diag.print(diag.Severity.Ok, "Loading plugin '{s}' with ABI v{d}, schema range {d}-{d}", .{ plugin_id_slice, api.abi_version, api.schema_min, api.schema_max }) catch {};

    // Validate ABI version
    if (api.abi_version != c.R2M_FRONTEND_API_VERSION) {
        diag.print(diag.Severity.Error, "ABI version mismatch: plugin v{d} != host v{d}", .{ api.abi_version, c.R2M_FRONTEND_API_VERSION }) catch {};
        lib.close();
        return error.ApiVersionMismatch;
    }

    // Validate schema compatibility
    if (api.schema_min > expected_schema.max or api.schema_max < expected_schema.min) {
        diag.print(diag.Severity.Error, "Schema version mismatch: plugin {d}-{d} incompatible with expected {d}-{d}", .{ api.schema_min, api.schema_max, expected_schema.min, expected_schema.max }) catch {};
        lib.close();
        return error.SchemaVersionMismatch;
    }

    diag.print(diag.Severity.Ok, "ABI negotiation successful for plugin '{s}'", .{plugin_id_slice}) catch {};

    // Validate mandatory function pointers
    if (api.wants_file == null or api.parse_file == null) {
        lib.close();
        return error.MissingRequiredFunctions;
    }

    // Validate plugin ID
    if (api.id == null) {
        lib.close();
        return error.MissingPluginId;
    }

    const plugin_id = try allocator.dupe(u8, std.mem.span(api.id));
    errdefer allocator.free(plugin_id);

    const plugin_abi_version = try std.fmt.allocPrint(allocator, "{d}", .{api.abi_version});
    errdefer allocator.free(plugin_abi_version);

    const plugin_semver = blk: {
        if (api.collect_manifest) |collect_fn| {
            var summary = std.mem.zeroes(c.r2m_plugin_summary_t);
            const status = collect_fn(&summary);
            if (status == c.R2M_STATUS_OK and summary.version.len > 0 and summary.version.data != null) {
                break :blk try allocator.dupe(u8, summary.version.data[0..summary.version.len]);
            }
        }
        break :blk try std.fmt.allocPrint(allocator, "{d}", .{api.api_version});
    };
    errdefer allocator.free(plugin_semver);

    // Initialize host services
    var host_services = HostServices{
        .allocator = allocator,
        .plugin_id = plugin_id,
        .plugin_abi_version = plugin_abi_version,
        .plugin_semver = plugin_semver,
    };

    // Initialize plugin if it has an init function
    if (api.init) |init_fn| {
        const init_context = c.r2m_init_context_t{
            .host = &host_services.createHostTable(),
            .plugin_path = std.mem.zeroes(c.r2m_path_view_t),
            .config_args = null,
            .config_arg_count = 0,
            .abi_version = c.R2M_FRONTEND_API_VERSION,
            .struct_size = @sizeOf(c.r2m_init_context_t),
            .reserved = .{ null, null, null },
        };

        const init_status = init_fn(&init_context);
        if (init_status != c.R2M_STATUS_OK) {
            lib.close();
            return error.PluginInitFailed;
        }
    }

    return LoadedFrontend{
        .lib = lib,
        .api = api,
        .plugin_id = plugin_id,
        .plugin_abi_version = plugin_abi_version,
        .plugin_semver = plugin_semver,
        .schema_min = api.schema_min,
        .schema_max = api.schema_max,
        .owns_semver = true,
        .allocator = allocator,
        .host_services = host_services,
    };
}

/// Resolve platform-specific library path
fn resolveLibraryPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    // If path already has a known extension, use as-is
    if (std.mem.endsWith(u8, path, ".so") or
        std.mem.endsWith(u8, path, ".dylib") or
        std.mem.endsWith(u8, path, ".dll"))
    {
        return allocator.dupe(u8, path);
    }

    // Otherwise, add platform-specific extension
    const extension = switch (@import("builtin").target.os.tag) {
        .linux => ".so",
        .macos => ".dylib",
        .windows => ".dll",
        else => return error.UnsupportedPlatform,
    };

    const lib_path = try allocator.alloc(u8, path.len + extension.len);
    @memcpy(lib_path[0..path.len], path);
    @memcpy(lib_path[path.len..], extension);
    return lib_path;
}

/// Error set for plugin loading
pub const LoadError = error{
    PluginNotFound,
    InvalidPlugin,
    UnableToLoadPlugin,
    MissingEntryPoint,
    NullPluginInterface,
    ApiVersionMismatch,
    SchemaVersionMismatch,
    MissingRequiredFunctions,
    MissingPluginId,
    PluginInitFailed,
    UnsupportedPlatform,
    OutOfMemory,
};

/// Test helper to validate plugin loading
pub fn testPluginLoad(plugin_path: []const u8) !void {
    const schema_range = SchemaRange{
        .min = c.R2M_SCHEMA_VERSION,
        .max = c.R2M_SCHEMA_VERSION,
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var frontend = try loadFrontend(allocator, plugin_path, schema_range);
    defer frontend.deinit();

    // Test that we can call wants_file
    const test_path = "test.zig";
    const wants = frontend.wantsFile(test_path);
    _ = wants;

    // Test basic plugin info
    std.debug.assert(frontend.api.id != null);
    std.debug.assert(frontend.api.abi_version == c.R2M_FRONTEND_API_VERSION);
}
