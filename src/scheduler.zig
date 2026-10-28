const std = @import("std");
const discovery = @import("discovery");
const plugin_loader = @import("plugin_loader");
const ir = @import("ir");
const diag = @import("diag");
const resolver = @import("resolver");
const path_resolver = @import("path_resolver");
const plugins_disabled = plugin_loader.plugins_disabled;
const c = if (plugins_disabled)
    struct {
        pub const R2M_SCHEMA_VERSION: u32 = 0;
    }
else
    @cImport(@cInclude("frontend.h"));

/// Scheduler errors that can occur during parallel processing
pub const Error = error{
    OutOfMemory,
    ThreadCreation,
    PluginNotFound,
    PluginLoadFailed,
    InvalidConfig,
    PermissionDenied,
    SystemResources,
    Unexpected,
    Unsupported,
    LockedMemoryLimitExceeded,
    ThreadQuotaExceeded,
};

/// Cache result type for function pointers
pub const CacheResult = struct {
    nodes: []ir.Node,
    edges: []ir.Edge,
    diagnostics: []ir.Diagnostic,
};

pub const PluginSummary = struct {
    id: []const u8,
    version: []const u8,
    schema_min: u32,
    schema_max: u32,
};

/// Options for configuring scheduler behavior
pub const RunOptions = struct {
    /// Whether to emit verbose diagnostics
    verbose: bool = false,
    /// Number of worker threads (0 = auto-detect CPU count)
    thread_count: usize = 0,
    /// Maximum batch size per worker
    batch_size: usize = 10,
    /// Plugin directory path
    plugin_dir: ?[]const u8 = null,
    /// Root path for resolving relative file paths
    root_path: ?[]const u8 = null,
    /// Cache manager for incremental builds
    cache_manager: ?*anyopaque = null,

    /// Cache get function pointer (set by main)
    cache_get_fn: ?*const fn (ptr: *anyopaque, file_path: []const u8, plugin_id: []const u8, plugin_abi_version: []const u8, plugin_semver: []const u8, file_content: []const u8) ?CacheResult = null,

    /// Cache put function pointer (set by main)
    cache_put_fn: ?*const fn (ptr: *anyopaque, file_path: []const u8, plugin_id: []const u8, plugin_abi_version: []const u8, plugin_semver: []const u8, file_content: []const u8, nodes: []const ir.Node, edges: []const ir.Edge, diagnostics: []const ir.Diagnostic) void = null,
};

/// Work item for processing a single source unit
const WorkItem = struct {
    unit: discovery.SourceUnit,
    result: ProcessResult,

    const ProcessResult = struct {
        success: bool,
        error_message: ?[]const u8 = null,
        processing_time_ms: u64 = 0,
        nodes: []ir.Node = &.{},
        edges: []ir.Edge = &.{},
        diagnostics: []ir.Diagnostic = &.{},
    };
};

/// Worker context for thread processing
const WorkerContext = struct {
    allocator: std.mem.Allocator,
    work_items: []WorkItem,
    start_index: usize,
    end_index: usize,
    options: RunOptions,
    plugins: []plugin_loader.LoadedFrontend,

    fn process(context: WorkerContext) void {
        const start_time = std.time.nanoTimestamp();

        for (context.work_items) |*work_item| {
            work_item.result = processUnit(context.allocator, work_item.unit, context.options, context.plugins) catch |err| switch (err) {
                error.OutOfMemory => {
                    work_item.result = .{
                        .success = false,
                        .error_message = "Out of memory during processing",
                    };
                    return;
                },
            };
        }

        const end_time = std.time.nanoTimestamp();
        const total_time_ms = @as(u64, @intCast(@divTrunc(end_time - start_time, std.time.ns_per_ms)));

        const processed_count = context.work_items.len;
        if (processed_count == 0) return;

        // Update processing times for all work items
        for (context.work_items) |*work_item| {
            work_item.result.processing_time_ms = total_time_ms / @as(u64, @intCast(processed_count));
        }
    }
};

/// Process a single source unit using the plugin system
fn processUnit(allocator: std.mem.Allocator, unit: discovery.SourceUnit, options: RunOptions, plugins: []plugin_loader.LoadedFrontend) !WorkItem.ProcessResult {
    // Validate required fields
    if (unit.path.len == 0) {
        return WorkItem.ProcessResult{
            .success = false,
            .error_message = "Empty path",
        };
    }

    // Find a plugin that wants to handle this file
    var selected_plugin: ?plugin_loader.LoadedFrontend = null;
    for (plugins) |plugin| {
        if (plugin.wantsFile(unit.path)) {
            selected_plugin = plugin;
            break;
        }
    }

    if (selected_plugin) |plugin| {
        // Read the file content - need to join with root path since unit.path is relative
        const abs_path = try std.fs.path.join(allocator, &.{ options.root_path orelse ".", unit.path });
        defer allocator.free(abs_path);

        const file_content = std.fs.cwd().readFileAlloc(allocator, abs_path, 1024 * 1024 * 10) catch |err| switch (err) {
            error.FileNotFound => {
                return WorkItem.ProcessResult{
                    .success = false,
                    .error_message = try std.fmt.allocPrint(allocator, "File not found: {s}", .{unit.path}),
                };
            },
            error.IsDir => {
                return WorkItem.ProcessResult{
                    .success = false,
                    .error_message = try std.fmt.allocPrint(allocator, "Path is a directory: {s}", .{unit.path}),
                };
            },
            else => {
                return WorkItem.ProcessResult{
                    .success = false,
                    .error_message = try std.fmt.allocPrint(allocator, "Failed to read file: {s}", .{@errorName(err)}),
                };
            },
        };
        defer allocator.free(file_content);

        // Check cache first if available
        if (options.cache_manager != null and options.cache_get_fn != null) {
            const plugin_abi_version = try std.fmt.allocPrint(allocator, "{d}", .{plugin.api.abi_version});
            defer allocator.free(plugin_abi_version);
            const plugin_semver = plugin.plugin_semver;

            if (options.cache_get_fn.?(options.cache_manager.?, unit.path, plugin.plugin_id, plugin_abi_version, plugin_semver, file_content)) |cached_entry| {
                if (options.verbose) {
                    std.debug.print("Cache hit for {s}: {d} nodes, {d} edges\n", .{ unit.path, cached_entry.nodes.len, cached_entry.edges.len });
                }

                // Return cached results
                return WorkItem.ProcessResult{
                    .success = true,
                    .nodes = cached_entry.nodes,
                    .edges = cached_entry.edges,
                    .diagnostics = cached_entry.diagnostics,
                };
            } else {
                if (options.verbose) {
                    std.debug.print("Cache miss for {s}\n", .{unit.path});
                }
            }
        }

        // Create an arena for this parsing operation
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        // Parse the file using the plugin with persistent allocator
        const parse_result = plugin.parseFile(unit.path, file_content, allocator, 1024 * 1024) catch |err| {
            return WorkItem.ProcessResult{
                .success = false,
                .error_message = try std.fmt.allocPrint(allocator, "Parse error: {s}", .{@errorName(err)}),
            };
        };

        if (options.verbose) {
            std.debug.print("Plugin returned {d} nodes, {d} edges for {s}\n", .{ parse_result.nodes.len, parse_result.edges.len, unit.path });
        }

        // Deep copy nodes and edges to persistent memory before arena is destroyed
        // Add reasonable limits to prevent OOM
        const max_nodes = 1000;
        const max_edges = 2000;
        const max_diagnostics = 100;

        if (parse_result.nodes.len > max_nodes) {
            return WorkItem.ProcessResult{
                .success = false,
                .error_message = try std.fmt.allocPrint(allocator, "Too many nodes: {d} (max {d})", .{ parse_result.nodes.len, max_nodes }),
            };
        }

        if (parse_result.edges.len > max_edges) {
            return WorkItem.ProcessResult{
                .success = false,
                .error_message = try std.fmt.allocPrint(allocator, "Too many edges: {d} (max {d})", .{ parse_result.edges.len, max_edges }),
            };
        }

        if (options.verbose) {
            std.debug.print("Allocating {d} nodes for deep copy\n", .{parse_result.nodes.len});
        }

        const copied_nodes = try allocator.alloc(ir.Node, parse_result.nodes.len);
        errdefer allocator.free(copied_nodes);

        for (parse_result.nodes, 0..) |node, i| {
            if (options.verbose) {
                std.debug.print("Copying node {d}: id_len={d}, name_len={d}\n", .{ i, node.id.len, node.name.len });
            }

            // Validate string lengths to detect corruption
            const max_string_len = 10000;
            if (node.id.len > max_string_len or node.name.len > max_string_len or
                node.fqname.len > max_string_len or node.file.len > max_string_len)
            {
                return WorkItem.ProcessResult{
                    .success = false,
                    .error_message = try std.fmt.allocPrint(allocator, "Node {d} has invalid string lengths: id={d}, name={d}, fqname={d}, file={d}", .{ i, node.id.len, node.name.len, node.fqname.len, node.file.len }),
                };
            }

            copied_nodes[i] = .{
                .id = try allocator.dupe(u8, node.id),
                .lang = try allocator.dupe(u8, node.lang),
                .kind = node.kind,
                .name = try allocator.dupe(u8, node.name),
                .fqname = try allocator.dupe(u8, node.fqname),
                .file = try allocator.dupe(u8, node.file),
                .range = node.range,
                .signature = if (node.signature) |sig| try allocator.dupe(u8, sig) else null,
                .visibility = node.visibility,
                .origin_plugin = try allocator.dupe(u8, node.origin_plugin),
                .module_id = if (node.module_id) |module_id| try allocator.dupe(u8, module_id) else null,
                .tags = try allocator.dupe([]const u8, node.tags),
            };
        }

        const copied_edges = try allocator.alloc(ir.Edge, parse_result.edges.len);
        errdefer allocator.free(copied_edges);

        for (parse_result.edges, 0..) |edge, i| {
            copied_edges[i] = .{
                .src = try allocator.dupe(u8, edge.src),
                .dst = try allocator.dupe(u8, edge.dst),
                .rel = edge.rel,
                .certainty = edge.certainty,
                .certainty_reason = if (edge.certainty_reason) |reason| try allocator.dupe(u8, reason) else null,
                .evidence_paths = blk: {
                    const paths = try allocator.alloc([]const u8, edge.evidence_paths.len);
                    for (paths, edge.evidence_paths) |*path, source| path.* = try allocator.dupe(u8, source);
                    break :blk paths;
                },
                .evidence_lines = try allocator.dupe(u32, edge.evidence_lines),
                .diagnostics = try allocator.dupe(ir.DiagnosticRef, edge.diagnostics),
            };
        }

        if (parse_result.diagnostics.len > max_diagnostics) {
            return WorkItem.ProcessResult{
                .success = false,
                .error_message = try std.fmt.allocPrint(allocator, "Too many diagnostics: {d} (max {d})", .{ parse_result.diagnostics.len, max_diagnostics }),
            };
        }

        const copied_diagnostics = try allocator.alloc(ir.Diagnostic, parse_result.diagnostics.len);
        errdefer allocator.free(copied_diagnostics);

        for (parse_result.diagnostics, 0..) |diagnostic, i| {
            copied_diagnostics[i] = .{
                .id = try allocator.dupe(u8, diagnostic.id),
                .severity = diagnostic.severity,
                .message = try allocator.dupe(u8, diagnostic.message),
                .file = try allocator.dupe(u8, diagnostic.file),
                .range = diagnostic.range,
                .tags = try allocator.dupe([]const u8, diagnostic.tags),
            };
        }

        // Store results in cache if available
        if (options.cache_manager != null and options.cache_put_fn != null) {
            const plugin_abi_version = try std.fmt.allocPrint(allocator, "{d}", .{plugin.api.abi_version});
            defer allocator.free(plugin_abi_version);
            const plugin_semver = plugin.plugin_semver;

            options.cache_put_fn.?(options.cache_manager.?, unit.path, plugin.plugin_id, plugin_abi_version, plugin_semver, file_content, copied_nodes, copied_edges, copied_diagnostics);
        }

        // Convert plugin result to WorkItem.ProcessResult with deep copied data
        return WorkItem.ProcessResult{
            .success = parse_result.success,
            .nodes = copied_nodes,
            .edges = copied_edges,
            .diagnostics = copied_diagnostics,
        };
    } else {
        // No loaded plugin handles this language (C has none yet): contribute nothing.
        if (options.verbose) std.debug.print("No plugin for {s}; skipping\n", .{unit.path});
        return WorkItem.ProcessResult{ .success = true };
    }
}

/// Result from running the scheduler
pub const RunResult = struct {
    nodes: []ir.Node,
    edges: []ir.Edge,
    diagnostics: []ir.Diagnostic,
    allocator: std.mem.Allocator,
    plugins_used: []PluginSummary,
    total_time_ns: u64,

    // Resolution statistics
    resolution_stats: struct {
        total_symbols: u32,
        resolved_refs: u32,
        unresolved_refs: u32,
        cross_lang_resolutions: u32,
        resolution_rate: f32,
    },

    pub fn deinit(self: RunResult) void {
        // Deep free nodes (cache-duplicated data)
        for (self.nodes) |node| {
            self.allocator.free(node.id);
            self.allocator.free(node.lang);
            self.allocator.free(node.name);
            self.allocator.free(node.fqname);
            self.allocator.free(node.file);
            if (node.signature) |sig| self.allocator.free(sig);
            self.allocator.free(node.origin_plugin);
            if (node.module_id) |module_id| self.allocator.free(module_id);
            // Free individual tag strings before freeing the tags array
            for (node.tags) |tag| {
                self.allocator.free(tag);
            }
            self.allocator.free(node.tags);
        }
        self.allocator.free(self.nodes);

        // Deep free edges (cache-duplicated data)
        for (self.edges) |edge| {
            self.allocator.free(edge.src);
            self.allocator.free(edge.dst);
            if (edge.certainty_reason) |reason| self.allocator.free(reason);
            // Free individual evidence path strings before freeing the array
            for (edge.evidence_paths) |path| {
                self.allocator.free(path);
            }
            self.allocator.free(edge.evidence_paths);
            self.allocator.free(edge.evidence_lines);
            // Free individual diagnostic ref IDs before freeing the array
            for (edge.diagnostics) |diag_ref| {
                self.allocator.free(diag_ref.id);
            }
            self.allocator.free(edge.diagnostics);
        }
        self.allocator.free(self.edges);

        // Deep free diagnostics (cache-duplicated data)
        for (self.diagnostics) |diag_item| {
            self.allocator.free(diag_item.id);
            self.allocator.free(diag_item.message);
            self.allocator.free(diag_item.file);
            // Free individual tag strings before freeing the tags array
            for (diag_item.tags) |tag| {
                self.allocator.free(tag);
            }
            self.allocator.free(diag_item.tags);
        }
        self.allocator.free(self.diagnostics);

        if (self.plugins_used.len > 0) {
            self.allocator.free(self.plugins_used);
        }
    }
};

/// Execute the scheduling pipeline over the provided discovery results using
/// parallel worker threads for improved performance.
pub fn run(units: []const discovery.SourceUnit, options: RunOptions) Error!RunResult {
    const gpa = std.heap.page_allocator;
    const run_start = std.time.nanoTimestamp();

    // Basic validation
    if (units.len == 0) {
        if (options.verbose) {
            std.debug.print("Scheduler: No units to process\n", .{});
        }
        return RunResult{
            .nodes = &[_]ir.Node{},
            .edges = &[_]ir.Edge{},
            .diagnostics = &[_]ir.Diagnostic{},
            .allocator = gpa,
            .plugins_used = &.{},
            .resolution_stats = .{
                .total_symbols = 0,
                .resolved_refs = 0,
                .unresolved_refs = 0,
                .cross_lang_resolutions = 0,
                .resolution_rate = 0.0,
            },
            .total_time_ns = 0,
        };
    }

    if (plugins_disabled) {
        if (options.verbose) {
            std.debug.print("Scheduler: Plugin loading disabled (-Dno_plugins)\n", .{});
        }
        return RunResult{
            .nodes = &[_]ir.Node{},
            .edges = &[_]ir.Edge{},
            .diagnostics = &[_]ir.Diagnostic{},
            .allocator = gpa,
            .plugins_used = &.{},
            .resolution_stats = .{
                .total_symbols = 0,
                .resolved_refs = 0,
                .unresolved_refs = 0,
                .cross_lang_resolutions = 0,
                .resolution_rate = 0.0,
            },
            .total_time_ns = 0,
        };
    }

    // Load plugins
    var resolved_plugin_dirs: [][]u8 = &.{};
    var resolved_plugin_dirs_owned = false;
    defer if (resolved_plugin_dirs_owned) path_resolver.freeDirList(std.heap.page_allocator, resolved_plugin_dirs);

    // Fallback: plugins installed next to the binary (zig-out and release archives share this layout).
    var exe_dir_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var bundled_dir_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const bundled_plugin_dir: []const u8 = blk: {
        const exe_dir = std.fs.selfExeDirPath(&exe_dir_buffer) catch break :blk "zig-out/lib/repo2mmd/plugins";
        break :blk std.fmt.bufPrint(&bundled_dir_buffer, "{s}/../lib/repo2mmd/plugins", .{exe_dir}) catch "zig-out/lib/repo2mmd/plugins";
    };

    var plugin_dir: []const u8 = undefined;
    const bundled_plugins_present = if (std.fs.cwd().access(bundled_plugin_dir, .{})) |_| true else |_| false;
    if (options.plugin_dir) |explicit_plugin_dir| {
        plugin_dir = explicit_plugin_dir;
    } else if (std.posix.getenv("REPO2MMD_PLUGIN_DIRS") == null and bundled_plugins_present) {
        // Plugins shipped with this binary win over the XDG data dir, which may
        // hold plugins from another version.
        plugin_dir = bundled_plugin_dir;
    } else {
        const plugin_dirs_opt: ?[][]u8 = blk: {
            const dirs = path_resolver.getPluginDirs(std.heap.page_allocator, .{}) catch |err| switch (err) {
                error.MissingHome, error.InvalidLegacyPath => break :blk null,
                error.OutOfMemory => return Error.OutOfMemory,
            };
            break :blk dirs;
        };

        if (plugin_dirs_opt) |dirs| {
            resolved_plugin_dirs = dirs;
            resolved_plugin_dirs_owned = true;
            if (dirs.len > 0) {
                plugin_dir = dirs[0];
                const dir_test = std.fs.openDirAbsolute(plugin_dir, .{}) catch null;
                if (dir_test) |dir_handle| {
                    var owned = dir_handle;
                    owned.close();
                } else {
                    plugin_dir = bundled_plugin_dir;
                }
            } else {
                plugin_dir = bundled_plugin_dir;
            }
        } else {
            plugin_dir = bundled_plugin_dir;
        }
    }
    var plugins = try std.ArrayList(plugin_loader.LoadedFrontend).initCapacity(gpa, 0);
    defer {
        for (plugins.items) |*plugin| {
            plugin.deinit();
        }
        plugins.deinit(gpa);
    }

    // Load all available plugins
    const schema_range = plugin_loader.SchemaRange{
        .min = c.R2M_SCHEMA_VERSION,
        .max = c.R2M_SCHEMA_VERSION,
    };

    // Try to load known plugins directly (specific plugins first)
    const known_plugins = [_][]const u8{ "zig", "typescript", "c" };
    for (known_plugins) |plugin_name| {
        const plugin_filename = try std.fmt.allocPrint(gpa, "librepo2mmd_{s}.so", .{plugin_name});
        defer gpa.free(plugin_filename);

        const plugin_path = try std.fs.path.join(gpa, &.{ plugin_dir, plugin_filename });
        defer gpa.free(plugin_path);

        const plugin = plugin_loader.loadFrontend(gpa, plugin_path, schema_range) catch |err| {
            if (options.verbose) {
                std.debug.print("Failed to load plugin {s}: {s}\n", .{ plugin_path, @errorName(err) });
            }
            continue;
        };

        try plugins.append(gpa, plugin);
        if (options.verbose) {
            std.debug.print("Loaded plugin: {s}\n", .{plugin.plugin_id});
        }
    }

    if (plugins.items.len == 0) {
        return Error.PluginNotFound;
    }

    if (options.verbose) {
        std.debug.print("Scheduler: Loaded {d} plugins\n", .{plugins.items.len});
    }

    var plugin_summaries: []PluginSummary = &.{};
    var plugin_summary_init_count: usize = 0;
    const plugin_summary_capacity = plugins.items.len;
    if (plugin_summary_capacity != 0) {
        plugin_summaries = try gpa.alloc(PluginSummary, plugin_summary_capacity);
    }
    errdefer {
        for (plugin_summaries[0..plugin_summary_init_count]) |summary| {
            gpa.free(summary.id);
            gpa.free(summary.version);
        }
        if (plugin_summary_capacity != 0) {
            gpa.free(plugin_summaries);
        }
    }

    if (plugin_summary_capacity != 0) {
        for (plugins.items, 0..) |plugin, idx| {
            plugin_summaries[idx] = .{
                .id = try gpa.dupe(u8, plugin.plugin_id),
                .version = try gpa.dupe(u8, plugin.plugin_semver),
                .schema_min = plugin.schema_min,
                .schema_max = plugin.schema_max,
            };
            plugin_summary_init_count = idx + 1;
        }
    }

    // Create work items
    var work_items = try gpa.alloc(WorkItem, units.len);
    defer gpa.free(work_items);

    for (units, 0..) |unit, i| {
        work_items[i] = .{
            .unit = unit,
            .result = .{
                .success = false,
                .error_message = null,
                .processing_time_ms = 0,
                .nodes = &.{},
                .edges = &.{},
                .diagnostics = &.{},
            },
        };
    }

    // Determine thread count
    const thread_count = if (options.thread_count == 0)
        try std.Thread.getCpuCount()
    else
        options.thread_count;

    // Calculate batch size
    const batch_size = if (options.batch_size == 0)
        @max(1, units.len / thread_count)
    else
        options.batch_size;

    if (options.verbose) {
        std.debug.print("Scheduler: Processing {d} units using {d} threads\n", .{ units.len, thread_count });
        std.debug.print("Scheduler: Using {d} batches of size up to {d}\n", .{ (units.len + batch_size - 1) / batch_size, batch_size });
    }

    // Simple fix: Process all batches sequentially for now
    // TODO: Implement proper parallel processing
    var start_index: usize = 0;
    while (start_index < units.len) {
        const end_index = @min(start_index + batch_size, units.len);

        const context = WorkerContext{
            .allocator = gpa,
            .work_items = work_items[start_index..end_index],
            .start_index = start_index,
            .end_index = end_index,
            .options = options,
            .plugins = plugins.items,
        };

        // Process batch directly without spawning a thread
        WorkerContext.process(context);

        start_index += batch_size;
    }

    // Collect results and check for errors
    var error_count: usize = 0;
    var total_processing_time_ms: u64 = 0;

    for (work_items) |work_item| {
        if (!work_item.result.success) {
            error_count += 1;
            if (options.verbose) {
                if (work_item.result.error_message) |msg| {
                    std.debug.print("Error processing {s}: {s}\n", .{ work_item.unit.path, msg });
                } else {
                    std.debug.print("Error processing {s}: (no error message)\n", .{work_item.unit.path});
                }
            }
        }
        total_processing_time_ms += work_item.result.processing_time_ms;
    }

    if (options.verbose) {
        std.debug.print("Scheduler completed: {d} successful, {d} errors, avg time: {d}ms\n", .{
            units.len - error_count,
            error_count,
            if (units.len > 0) total_processing_time_ms / units.len else 0,
        });
    }

    // Collect all nodes, edges, and diagnostics from successful work items
    var total_nodes: usize = 0;
    var total_edges: usize = 0;
    var total_diagnostics: usize = 0;

    for (work_items) |work_item| {
        if (work_item.result.success) {
            total_nodes += work_item.result.nodes.len;
            total_edges += work_item.result.edges.len;
            total_diagnostics += work_item.result.diagnostics.len;
        }
    }

    // Allocate result arrays
    var all_nodes = try gpa.alloc(ir.Node, total_nodes);
    var all_edges = try gpa.alloc(ir.Edge, total_edges);
    var all_diagnostics = try gpa.alloc(ir.Diagnostic, total_diagnostics);

    // Copy results from work items
    var node_offset: usize = 0;
    var edge_offset: usize = 0;
    var diagnostic_offset: usize = 0;

    for (work_items) |work_item| {
        if (work_item.result.success) {
            @memcpy(all_nodes[node_offset .. node_offset + work_item.result.nodes.len], work_item.result.nodes);
            @memcpy(all_edges[edge_offset .. edge_offset + work_item.result.edges.len], work_item.result.edges);
            @memcpy(all_diagnostics[diagnostic_offset .. diagnostic_offset + work_item.result.diagnostics.len], work_item.result.diagnostics);

            node_offset += work_item.result.nodes.len;
            edge_offset += work_item.result.edges.len;
            diagnostic_offset += work_item.result.diagnostics.len;
        }
    }

    // Use resolver to process edges and generate enhanced diagnostics
    const resolver_config = resolver.ResolverConfig{
        .max_unresolved_refs = 5000,
        .cross_language_resolution = true,
        .max_resolution_depth = 50,
        .collect_diagnostics = true,
        .warn_threshold = 1000,
        .error_threshold = 2000,
    };
    var resolver_impl = try resolver.Resolver.init(gpa, resolver_config);
    defer resolver_impl.deinit();

    // Build symbol tables from all nodes
    resolver_impl.buildSymbolTables(all_nodes) catch |err| {
        if (options.verbose) {
            std.debug.print("Failed to build symbol tables: {s}\n", .{@errorName(err)});
        }
        return Error.Unexpected;
    };

    // Resolve all edges using enhanced resolver with cross-language support
    const resolved_edges = resolver_impl.resolveEdges(all_nodes, all_edges) catch |err| {
        if (options.verbose) {
            std.debug.print("Failed to resolve edges: {s}\n", .{@errorName(err)});
        }
        return Error.Unexpected;
    };

    // No resolver diagnostics for now

    // A file that cannot be parsed (no plugin for its language, read error,
    // plugin failure) becomes a warning diagnostic instead of failing the run.
    var combined_diagnostics = try gpa.alloc(ir.Diagnostic, all_diagnostics.len + error_count);
    @memcpy(combined_diagnostics[0..all_diagnostics.len], all_diagnostics);
    var skipped_index = all_diagnostics.len;
    for (work_items) |work_item| {
        if (work_item.result.success) continue;
        const message = work_item.result.error_message orelse "processing failed";
        std.debug.print("warning: skipped {s}: {s}\n", .{ work_item.unit.path, message });
        combined_diagnostics[skipped_index] = .{
            .id = try gpa.dupe(u8, "R2M-SKIPPED-FILE"),
            .severity = .Warn,
            .message = try gpa.dupe(u8, message),
            .file = try gpa.dupe(u8, work_item.unit.path),
            .range = std.mem.zeroes(ir.Range),
            .tags = try gpa.alloc([]const u8, 0),
        };
        skipped_index += 1;
    }

    // Get resolver statistics
    const resolver_stats = resolver_impl.getStats();

    if (options.verbose) {
        std.debug.print("Resolver: {d}/{d} edges resolved ({d:.1}%)\n", .{ resolved_edges.len, all_edges.len, resolver_stats.resolution_rate });
        std.debug.print("Resolver: Generated 0 enhanced diagnostics\n", .{});
    }

    return RunResult{
        .nodes = all_nodes,
        .edges = resolved_edges,
        .diagnostics = combined_diagnostics,
        .allocator = gpa,
        .plugins_used = plugin_summaries,
        .resolution_stats = .{
            .total_symbols = resolver_stats.total_symbols,
            .resolved_refs = resolver_stats.resolved_refs,
            .unresolved_refs = resolver_stats.unresolved_refs,
            .cross_lang_resolutions = resolver_stats.cross_lang_resolutions,
            .resolution_rate = resolver_stats.resolution_rate,
        },
        .total_time_ns = @as(u64, @intCast(std.time.nanoTimestamp() - run_start)),
    };
}
