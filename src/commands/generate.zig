const std = @import("std");
const cli = @import("../cli.zig");
const diag = @import("diag");
const ir = @import("ir");
const cache = @import("cache_mgr");
const scheduler = @import("scheduler");
const discovery = @import("discovery");
const json_emitter = @import("json_emitter");
const mermaid_emitter = @import("mermaid_emitter");

const GenerateOptions = struct {
    output: ?[]const u8 = null,
    format: ?[]const u8 = null,
    jobs: ?u32 = null,
    include_patterns: std.ArrayList([]const u8),
    exclude_patterns: std.ArrayList([]const u8),
    languages: std.ArrayList([]const u8),
    root: ?[]const u8 = null,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.include_patterns.deinit(allocator);
        self.exclude_patterns.deinit(allocator);
        self.languages.deinit(allocator);
    }
};

pub fn executeGenerate(allocator: std.mem.Allocator, global_opts: cli.GlobalOptions, args: []const []const u8) !void {
    var opts = GenerateOptions{
        .include_patterns = std.ArrayList([]const u8).initCapacity(allocator, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        },
        .exclude_patterns = std.ArrayList([]const u8).initCapacity(allocator, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        },
        .languages = std.ArrayList([]const u8).initCapacity(allocator, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        },
    };
    defer opts.deinit(allocator);

    var arg_idx: usize = 0;
    while (arg_idx < args.len) {
        const arg = args[arg_idx];
        if (std.mem.startsWith(u8, arg, "-")) {
            // Long options
            if (std.mem.startsWith(u8, arg, "--output=")) {
                opts.output = arg["--output=".len..];
            } else if (std.mem.startsWith(u8, arg, "--format=")) {
                opts.format = arg["--format=".len..];
            } else if (std.mem.startsWith(u8, arg, "--jobs=")) {
                const jobs_str = arg["--jobs=".len..];
                opts.jobs = try std.fmt.parseInt(u32, jobs_str, 10);
            } else if (std.mem.startsWith(u8, arg, "--include=")) {
                try opts.include_patterns.append(allocator, arg["--include=".len..]);
            } else if (std.mem.startsWith(u8, arg, "--exclude=")) {
                try opts.exclude_patterns.append(allocator, arg["--exclude=".len..]);
            } else if (std.mem.startsWith(u8, arg, "--language=")) {
                try opts.languages.append(allocator, arg["--language=".len..]);
            } else if (std.mem.startsWith(u8, arg, "--root=")) {
                opts.root = arg["--root=".len..];
            }
            // Short options with values
            else if (std.mem.startsWith(u8, arg, "-o")) {
                if (arg.len > 2) {
                    // -o<file>
                    opts.output = arg[2..];
                } else {
                    // -o <file>
                    arg_idx += 1;
                    if (arg_idx >= args.len) {
                        try diag.printError("Expected value after -o", .{});
                        return error.InvalidArgument;
                    }
                    opts.output = args[arg_idx];
                }
            } else if (std.mem.startsWith(u8, arg, "-f")) {
                if (arg.len > 2) {
                    // -f<format>
                    opts.format = arg[2..];
                } else {
                    // -f <format>
                    arg_idx += 1;
                    if (arg_idx >= args.len) {
                        try diag.printError("Expected value after -f", .{});
                        return error.InvalidArgument;
                    }
                    opts.format = args[arg_idx];
                }
            } else if (std.mem.startsWith(u8, arg, "-j")) {
                if (arg.len > 2) {
                    // -j<n>
                    const jobs_str = arg[2..];
                    opts.jobs = try std.fmt.parseInt(u32, jobs_str, 10);
                } else {
                    // -j <n>
                    arg_idx += 1;
                    if (arg_idx >= args.len) {
                        try diag.printError("Expected value after -j", .{});
                        return error.InvalidArgument;
                    }
                    const jobs_str = args[arg_idx];
                    opts.jobs = try std.fmt.parseInt(u32, jobs_str, 10);
                }
            }
            // Standalone short options
            else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
                arg_idx += 1;
                if (arg_idx >= args.len) {
                    try diag.printError("Expected value after {s}", .{arg});
                    return error.InvalidArgument;
                }
                opts.output = args[arg_idx];
            } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--format")) {
                arg_idx += 1;
                if (arg_idx >= args.len) {
                    try diag.printError("Expected value after {s}", .{arg});
                    return error.InvalidArgument;
                }
                opts.format = args[arg_idx];
            } else if (std.mem.eql(u8, arg, "-j") or std.mem.eql(u8, arg, "--jobs")) {
                arg_idx += 1;
                if (arg_idx >= args.len) {
                    try diag.printError("Expected value after {s}", .{arg});
                    return error.InvalidArgument;
                }
                const jobs_str = args[arg_idx];
                opts.jobs = try std.fmt.parseInt(u32, jobs_str, 10);
            } else if (std.mem.startsWith(u8, arg, "--include=")) {
                try opts.include_patterns.append(allocator, arg["--include=".len..]);
            } else if (std.mem.startsWith(u8, arg, "--exclude=")) {
                try opts.exclude_patterns.append(allocator, arg["--exclude=".len..]);
            } else if (std.mem.startsWith(u8, arg, "--language=")) {
                try opts.languages.append(allocator, arg["--language=".len..]);
            } else if (std.mem.startsWith(u8, arg, "--root=")) {
                opts.root = arg["--root=".len..];
            } else {
                try diag.printError("Unknown option: {s}", .{arg});
                return error.InvalidArgument;
            }
        } else {
            // Positional argument - treat as root path
            if (opts.root != null) {
                try diag.printError("Multiple root paths specified: {s} and {s}", .{ opts.root.?, arg });
                return error.InvalidArgument;
            }
            opts.root = arg;
        }
        arg_idx += 1;
    }

    // Set defaults
    const output_path = opts.output orelse "-";
    const format_arg = opts.format orelse
        if (std.mem.endsWith(u8, output_path, ".json")) "json" else "mermaid";
    const format = if (std.mem.eql(u8, format_arg, "mmd")) "mermaid" else format_arg;
    const jobs = opts.jobs orelse @min(4, try std.Thread.getCpuCount());
    const root_path = opts.root orelse ".";

    // Validate format
    if (!std.mem.eql(u8, format, "mermaid") and !std.mem.eql(u8, format, "json")) {
        try diag.printError("Invalid format: {s}. Supported formats: mmd, json", .{format});
        return error.InvalidArgument;
    }

    // Discover files
    var files = std.ArrayList([]const u8).initCapacity(allocator, 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer {
        for (files.items) |file_path| {
            allocator.free(file_path);
        }
        files.deinit(allocator);
    }

    const discovered_units = try discovery.scan(allocator, root_path);
    defer discovery.deinitUnits(allocator, discovered_units);

    // Convert SourceUnits to file paths, filtering by patterns and languages
    for (discovered_units) |unit| {
        if (unit.is_ignored) continue;

        // Check language filter
        if (opts.languages.items.len > 0) {
            const lang_match = for (opts.languages.items) |lang| {
                if (std.mem.eql(u8, lang, "zig") and unit.lang == .Zig) break true;
                if (std.mem.eql(u8, lang, "c") and unit.lang == .C) break true;
                if (std.mem.eql(u8, lang, "ts") and unit.lang == .Ts) break true;
            } else false;
            if (!lang_match) continue;
        }

        // Check include/exclude patterns
        const path_match = for (opts.include_patterns.items) |pattern| {
            if (std.mem.indexOf(u8, unit.path, pattern) != null) break true;
        } else (opts.include_patterns.items.len == 0);

        if (!path_match) continue;

        const exclude_match = for (opts.exclude_patterns.items) |pattern| {
            if (std.mem.indexOf(u8, unit.path, pattern) != null) break true;
        } else false;

        if (exclude_match) continue;

        const file_path = try allocator.dupe(u8, unit.path);
        try files.append(allocator, file_path);
    }

    if (files.items.len == 0) {
        try diag.printError("No files found to process", .{});
        return error.NoFilesFound;
    }

    // Initialize cache
    // No cache when disabled or when the cache directory cannot be set up.
    var cache_mgr: ?cache.CacheManager = if (global_opts.cache_mode == .off)
        null
    else
        cache.CacheManager.init(allocator) catch null;
    defer if (cache_mgr) |*manager| manager.deinit();

    // Convert file paths to SourceUnits
    var units = try allocator.alloc(discovery.SourceUnit, files.items.len);
    defer allocator.free(units);

    // Convert file paths to SourceUnits

    // Now fill the units array
    for (files.items, 0..) |file_path, i| {
        // Determine language from file extension
        const lang = if (std.mem.endsWith(u8, file_path, ".zig"))
            discovery.Language.Zig
        else if (std.mem.endsWith(u8, file_path, ".c") or std.mem.endsWith(u8, file_path, ".h"))
            discovery.Language.C
        else if (std.mem.endsWith(u8, file_path, ".ts") or std.mem.endsWith(u8, file_path, ".tsx"))
            discovery.Language.Ts
        else
            discovery.Language.Unknown;

        units[i] = discovery.SourceUnit{
            .path = file_path,
            .lang = lang,
            .module_id = "", // Will be filled by processing
            .is_ignored = false,
        };
    }

    // Get plugin directory from global options
    const plugin_dir = if (global_opts.plugin_dirs.items.len > 0) global_opts.plugin_dirs.items[0] else null;

    // Process files using scheduler
    var run_options = scheduler.RunOptions{
        .verbose = global_opts.verbose > 0,
        .thread_count = jobs,
        .plugin_dir = plugin_dir,
        .root_path = root_path,
        .cache_manager = if (cache_mgr) |*manager| manager else null,
        .cache_get_fn = struct {
            pub fn call(ptr: *anyopaque, file_path: []const u8, plugin_id: []const u8, plugin_abi_version: []const u8, plugin_semver: []const u8, file_content: []const u8) ?scheduler.CacheResult {
                const cache_mgr_inner = @as(*cache.CacheManager, @ptrCast(@alignCast(ptr)));
                // Use page_allocator to match the allocator used by RunResult
                const page_allocator = std.heap.page_allocator;
                const entry = cache_mgr_inner.get(page_allocator, file_path, plugin_id, plugin_abi_version, plugin_semver, file_content) catch return null;
                if (entry) |cache_entry| {
                    // We need to duplicate the cached data since the caller expects to own it
                    // but CacheEntry needs to be deinitialized after extracting the data
                    const nodes_dup = page_allocator.dupe(ir.Node, cache_entry.nodes) catch return null;
                    errdefer page_allocator.free(nodes_dup);

                    const edges_dup = page_allocator.dupe(ir.Edge, cache_entry.edges) catch return null;
                    errdefer page_allocator.free(edges_dup);

                    const diagnostics_arr_dup = page_allocator.dupe(ir.Diagnostic, cache_entry.diagnostics) catch return null;
                    errdefer page_allocator.free(diagnostics_arr_dup);

                    // Deep duplicate nodes by creating new structs
                    for (cache_entry.nodes, 0..) |node_orig, i| {
                        // Deep duplicate tags array
                        const tags_dup = page_allocator.alloc([]const u8, node_orig.tags.len) catch return null;
                        for (node_orig.tags, 0..) |tag, j| {
                            tags_dup[j] = page_allocator.dupe(u8, tag) catch return null;
                        }

                        nodes_dup[i] = ir.Node{
                            .id = page_allocator.dupe(u8, node_orig.id) catch return null,
                            .lang = page_allocator.dupe(u8, node_orig.lang) catch return null,
                            .kind = node_orig.kind,
                            .name = page_allocator.dupe(u8, node_orig.name) catch return null,
                            .fqname = page_allocator.dupe(u8, node_orig.fqname) catch return null,
                            .file = page_allocator.dupe(u8, node_orig.file) catch return null,
                            .range = node_orig.range,
                            .signature = if (node_orig.signature) |sig| page_allocator.dupe(u8, sig) catch return null else null,
                            .visibility = node_orig.visibility,
                            .origin_plugin = page_allocator.dupe(u8, node_orig.origin_plugin) catch return null,
                            .module_id = if (node_orig.module_id) |module_id| page_allocator.dupe(u8, module_id) catch return null else null,
                            .tags = tags_dup,
                        };
                    }

                    // Deep duplicate edges by creating new structs
                    for (cache_entry.edges, 0..) |edge_orig, i| {
                        // Deep duplicate evidence_paths array
                        const evidence_paths_dup = page_allocator.alloc([]const u8, edge_orig.evidence_paths.len) catch return null;
                        for (edge_orig.evidence_paths, 0..) |path, j| {
                            evidence_paths_dup[j] = page_allocator.dupe(u8, path) catch return null;
                        }

                        // Deep duplicate diagnostics array
                        const diagnostics_dup = page_allocator.alloc(ir.DiagnosticRef, edge_orig.diagnostics.len) catch return null;
                        for (edge_orig.diagnostics, 0..) |diag_ref, j| {
                            diagnostics_dup[j] = ir.DiagnosticRef{
                                .id = page_allocator.dupe(u8, diag_ref.id) catch return null,
                            };
                        }

                        edges_dup[i] = ir.Edge{
                            .src = page_allocator.dupe(u8, edge_orig.src) catch return null,
                            .dst = page_allocator.dupe(u8, edge_orig.dst) catch return null,
                            .rel = edge_orig.rel,
                            .certainty = edge_orig.certainty,
                            .certainty_reason = if (edge_orig.certainty_reason) |reason| page_allocator.dupe(u8, reason) catch return null else null,
                            .evidence_paths = evidence_paths_dup,
                            .evidence_lines = page_allocator.dupe(u32, edge_orig.evidence_lines) catch return null,
                            .diagnostics = diagnostics_dup,
                        };
                    }

                    // Deep duplicate diagnostics by creating new structs
                    for (cache_entry.diagnostics, 0..) |diag_orig, i| {
                        // Deep duplicate tags array
                        const diag_tags_dup = page_allocator.alloc([]const u8, diag_orig.tags.len) catch return null;
                        for (diag_orig.tags, 0..) |tag, j| {
                            diag_tags_dup[j] = page_allocator.dupe(u8, tag) catch return null;
                        }

                        diagnostics_arr_dup[i] = ir.Diagnostic{
                            .id = page_allocator.dupe(u8, diag_orig.id) catch return null,
                            .severity = diag_orig.severity,
                            .message = page_allocator.dupe(u8, diag_orig.message) catch return null,
                            .file = page_allocator.dupe(u8, diag_orig.file) catch return null,
                            .range = diag_orig.range,
                            .tags = diag_tags_dup,
                        };
                    }

                    // Now that we've successfully duplicated everything, clean up original entry
                    cache_entry.deinit(page_allocator);

                    return .{
                        .nodes = nodes_dup,
                        .edges = edges_dup,
                        .diagnostics = diagnostics_arr_dup,
                    };
                }
                return null;
            }
        }.call,
        .cache_put_fn = struct {
            pub fn call(ptr: *anyopaque, file_path: []const u8, plugin_id: []const u8, plugin_abi_version: []const u8, plugin_semver: []const u8, file_content: []const u8, nodes: []const ir.Node, edges: []const ir.Edge, diagnostics: []const ir.Diagnostic) void {
                const cache_mgr_inner = @as(*cache.CacheManager, @ptrCast(@alignCast(ptr)));
                cache_mgr_inner.put(file_path, plugin_id, plugin_abi_version, plugin_semver, file_content, nodes, edges, diagnostics) catch |err| {
                    diag.printError("Failed to write cache entry for {s}: {}", .{ file_path, err }) catch {};
                };
            }
        }.call,
    };

    if (global_opts.cache_mode != .rw) run_options.cache_put_fn = null;

    const result = try scheduler.run(units, run_options);
    defer result.deinit();

    // Create IR from result
    var edge_arena = std.heap.ArenaAllocator.init(allocator);
    defer edge_arena.deinit();
    const edges = try mergeDuplicateEdges(edge_arena.allocator(), result.edges);
    var generated_at_buffer: [20]u8 = undefined;

    const ir_data = ir.IR{
        .schema_version = 1,
        .graph = ir.Graph{
            .nodes = result.nodes,
            .edges = edges,
        },
        .manifest = ir.GraphManifest{
            .generated_at = formatGeneratedAt(&generated_at_buffer),
            .generator_version = @import("build_options").version,
            .graph_type = "dependency",
            .input_root = root_path,
            .schema_version = 1,
            .node_count = @intCast(result.nodes.len),
            .edge_count = @intCast(edges.len),
            .resolved_refs = result.resolution_stats.resolved_refs,
            .unresolved_refs = result.resolution_stats.unresolved_refs,
            .resolution_rate = result.resolution_stats.resolution_rate,
            .cache_hits = 0, // TODO: Get from cache manager
            .cache_misses = 0, // TODO: Get from cache manager
            .plugins_used = blk: {
                const ir_plugins = try allocator.alloc(ir.PluginSummary, result.plugins_used.len);
                for (result.plugins_used, 0..) |plugin, i| {
                    ir_plugins[i] = ir.PluginSummary{
                        .id = plugin.id,
                        .version = plugin.version,
                        .schema_min = plugin.schema_min,
                        .schema_max = plugin.schema_max,
                    };
                }
                break :blk ir_plugins;
            },
            .cli_args = &[_][]const u8{}, // TODO: Capture actual CLI args
        },
        .diagnostics = blk: {
            const full_diagnostics = try allocator.alloc(ir.FullDiagnostic, result.diagnostics.len);
            for (result.diagnostics, 0..) |source_diag, i| {
                full_diagnostics[i] = ir.FullDiagnostic{
                    .id = source_diag.id,
                    .severity = source_diag.severity,
                    .code = "GENERIC", // TODO: Use actual diagnostic codes
                    .message = source_diag.message,
                    .file = source_diag.file,
                    .range = source_diag.range,
                    .plugin = null, // TODO: Track plugin source
                };
            }
            break :blk full_diagnostics;
        },
    };

    // Emit output
    const to_stdout = std.mem.eql(u8, output_path, "-");
    const output_dest = if (to_stdout) std.fs.File.stdout() else try std.fs.cwd().createFile(output_path, .{});
    defer if (!to_stdout) output_dest.close();

    var write_buffer: [4096]u8 = undefined;
    var writer = output_dest.writer(&write_buffer);
    if (std.mem.eql(u8, format, "json")) {
        var json_emitter_instance = json_emitter.JsonEmitter(@TypeOf(writer)).init(allocator, &writer);
        try json_emitter_instance.emit(ir_data);
    } else {
        var mermaid_emitter_instance = mermaid_emitter.MermaidFlowchartEmitter(@TypeOf(writer)).init(allocator, &writer);
        try mermaid_emitter_instance.emit(ir_data.graph, "Repository Dependencies");
    }
    try writer.interface.flush();

    // Clean up IR data
    allocator.free(ir_data.manifest.plugins_used);
    allocator.free(ir_data.diagnostics);

    // Print statistics
    const total_files = files.items.len;

    if (global_opts.verbose > 0) {
        std.debug.print("Processed {} files\n", .{total_files});
        std.debug.print("Output written to {s}\n", .{output_path});
    }
}

/// One edge per (src, dst, rel). A file that imports the same target twice
/// yields one edge whose evidence lists both sites, in first-seen order.
fn mergeDuplicateEdges(arena: std.mem.Allocator, edges: []const ir.Edge) ![]const ir.Edge {
    var merged = std.ArrayList(ir.Edge){};
    var index_by_key = std.StringHashMap(usize).init(arena);
    for (edges) |edge| {
        const key = try std.fmt.allocPrint(arena, "{s}\x00{s}\x00{s}", .{ edge.src, edge.dst, @tagName(edge.rel) });
        const entry = try index_by_key.getOrPut(key);
        if (!entry.found_existing) {
            entry.value_ptr.* = merged.items.len;
            try merged.append(arena, edge);
            continue;
        }
        const existing = &merged.items[entry.value_ptr.*];
        existing.evidence_paths = try std.mem.concat(arena, []const u8, &.{ existing.evidence_paths, edge.evidence_paths });
        existing.evidence_lines = try std.mem.concat(arena, u32, &.{ existing.evidence_lines, edge.evidence_lines });
    }
    return merged.items;
}

/// RFC 3339 UTC time from SOURCE_DATE_EPOCH when set (reproducible builds
/// convention), otherwise the current time.
fn formatGeneratedAt(buffer: *[20]u8) []const u8 {
    const seconds: u64 = blk: {
        if (std.posix.getenv("SOURCE_DATE_EPOCH")) |raw| {
            // Cap at 9999-12-31 so the year always fits four digits.
            if (std.fmt.parseInt(u64, raw, 10)) |value| {
                if (value <= 253402300799) break :blk value;
            } else |_| {}
        }
        break :blk @intCast(@max(0, std.time.timestamp()));
    };
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    }) catch unreachable;
}
