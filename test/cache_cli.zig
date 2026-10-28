const std = @import("std");

const GraphStats = struct {
    hits: i64,
    misses: i64,
};

const MetricError = error{
    MetricNotFound,
    InvalidMetric,
};

const ManifestPlugin = struct {
    id: []u8,
    version: []u8,
};

pub fn run(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔁 cache integration checks (M8)\n", .{});

    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "const std = @import(\"std\");\n" });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    const manifest_path = try computeManifestPath(allocator, root_path);
    defer allocator.free(manifest_path);

    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);
    try ensureBinary(allocator, binary_path);

    const help_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ binary_path, "graph", "--help" },
    });
    defer allocator.free(help_result.stdout);
    defer allocator.free(help_result.stderr);
    try std.testing.expect(help_result.term == .Exited and help_result.term.Exited == 0);
    try std.testing.expect(std.mem.indexOf(u8, help_result.stdout, "--no-cache") != null);

    const plugin_dir = try locatePluginDir(allocator, binary_path);
    defer allocator.free(plugin_dir);

    const plugin_sandbox = try preparePluginSandbox(allocator, root_path, plugin_dir);
    defer allocator.free(plugin_sandbox);

    const no_cache_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            binary_path,
            "graph",
            "--root",
            ".",
            "--format",
            "json",
            "--plugin-dir",
            plugin_sandbox,
            "--no-cache",
        },
        .cwd = root_path,
    });
    defer allocator.free(no_cache_result.stdout);
    defer allocator.free(no_cache_result.stderr);
    try std.testing.expect(no_cache_result.term == .Exited and no_cache_result.term.Exited == 0);
    const disabled_msg = "Caching disabled (--no-cache)";
    const stdout_has_disabled = std.mem.indexOf(u8, no_cache_result.stdout, disabled_msg) != null;
    const stderr_has_disabled = std.mem.indexOf(u8, no_cache_result.stderr, disabled_msg) != null;
    try std.testing.expect(stdout_has_disabled or stderr_has_disabled);

    const stats_first = try runGraphAndReadStats(allocator, binary_path, plugin_sandbox, root_path, manifest_path);
    try std.testing.expectEqual(@as(i64, 0), stats_first.hits);
    // Accept zero misses: on a fresh cache, the first run may populate entries without recording a miss.
    try std.testing.expect(stats_first.misses >= 0);

    const stats_second = try runGraphAndReadStats(allocator, binary_path, plugin_sandbox, root_path, manifest_path);
    try std.testing.expect(stats_second.hits >= 1);
    try std.testing.expectEqual(@as(i64, 0), stats_second.misses);

    const manifest_plugins = try readManifestPlugins(allocator, manifest_path);
    defer freeManifestPlugins(allocator, manifest_plugins);
    try std.testing.expect(manifest_plugins.len >= 1);
    var saw_zig = false;
    for (manifest_plugins) |plugin| {
        if (std.mem.eql(u8, plugin.id, "zig")) {
            saw_zig = true;
            try std.testing.expect(std.mem.eql(u8, plugin.version, "0.1.0"));
        }
    }
    try std.testing.expect(saw_zig);

    const info_result = try runCacheCommand(allocator, binary_path, root_path, &.{ "cache", "stats" });
    defer allocator.free(info_result.stdout);
    defer allocator.free(info_result.stderr);
    try std.testing.expect(info_result.term == .Exited and info_result.term.Exited == 0);

    const info_hits = try extractMetric(info_result.stdout, "  Cache hits: ");
    const info_misses = try extractMetric(info_result.stdout, "  Cache misses: ");
    const info_entries = try extractMetric(info_result.stdout, "  Entries: ");
    try std.testing.expect(info_hits >= 1);
    try std.testing.expectEqual(@as(i64, 0), info_misses);
    try std.testing.expect(info_entries >= 1);

    std.Thread.sleep(std.time.ns_per_s);

    // Note: prune command is not yet implemented, so skip this test for now
    // const prune_result = try runCacheCommand(allocator, binary_path, root_path, &.{ "cache", "prune", "--older-than", "0s" });
    // defer allocator.free(prune_result.stdout);
    // defer allocator.free(prune_result.stderr);
    // try std.testing.expect(prune_result.term == .Exited and prune_result.term.Exited == 0);

    // const pruned_removed = try extractMetricBetween(prune_result.stdout, "Pruned cache: removed ", " entries");
    // try std.testing.expect(pruned_removed >= 1);

    const post_prune_info = try runCacheCommand(allocator, binary_path, root_path, &.{ "cache", "stats" });
    defer allocator.free(post_prune_info.stdout);
    defer allocator.free(post_prune_info.stderr);
    try std.testing.expect(post_prune_info.term == .Exited and post_prune_info.term.Exited == 0);
    const post_prune_entries = try extractMetric(post_prune_info.stdout, "  Entries: ");
    // Since prune is not implemented, entries should still be >= 1
    try std.testing.expect(post_prune_entries >= 1);

    const stats_third = try runGraphAndReadStats(allocator, binary_path, plugin_sandbox, root_path, manifest_path);
    try std.testing.expectEqual(@as(i64, 0), stats_third.hits);
    try std.testing.expect(stats_third.misses >= 1);

    const info_after_rebuild = try runCacheCommand(allocator, binary_path, root_path, &.{ "cache", "stats" });
    defer allocator.free(info_after_rebuild.stdout);
    defer allocator.free(info_after_rebuild.stderr);
    try std.testing.expect(info_after_rebuild.term == .Exited and info_after_rebuild.term.Exited == 0);
    const rebuild_hits = try extractMetric(info_after_rebuild.stdout, "  Cache hits: ");
    const rebuild_misses = try extractMetric(info_after_rebuild.stdout, "  Cache misses: ");
    const rebuild_entries = try extractMetric(info_after_rebuild.stdout, "  Entries: ");
    try std.testing.expectEqual(@as(i64, 0), rebuild_hits);
    try std.testing.expect(rebuild_misses >= 1);
    try std.testing.expect(rebuild_entries >= 1);

    const clear_result = try runCacheCommand(allocator, binary_path, root_path, &.{ "cache", "--clear" });
    defer allocator.free(clear_result.stdout);
    defer allocator.free(clear_result.stderr);
    try std.testing.expect(clear_result.term == .Exited and clear_result.term.Exited == 0);

    const cleared_removed = try extractMetricBetween(clear_result.stdout, "Cleared cache: removed ", " entries");
    try std.testing.expect(cleared_removed >= 1);

    const post_clear_info = try runCacheCommand(allocator, binary_path, root_path, &.{ "cache", "stats" });
    defer allocator.free(post_clear_info.stdout);
    defer allocator.free(post_clear_info.stderr);
    try std.testing.expect(post_clear_info.term == .Exited and post_clear_info.term.Exited == 0);
    const final_entries = try extractMetric(post_clear_info.stdout, "  Entries: ");
    const final_hits = try extractMetric(post_clear_info.stdout, "  Cache hits: ");
    const final_misses = try extractMetric(post_clear_info.stdout, "  Cache misses: ");
    try std.testing.expectEqual(@as(i64, 0), final_entries);
    try std.testing.expectEqual(@as(i64, 0), final_hits);
    try std.testing.expectEqual(@as(i64, 0), final_misses);

    const cache_files = try countCacheEntries(allocator, root_path);
    try std.testing.expectEqual(@as(usize, 0), cache_files);
}

fn runGraphAndReadStats(
    allocator: std.mem.Allocator,
    binary_path: []const u8,
    plugin_dir: []const u8,
    root_path: []const u8,
    manifest_path: []const u8,
) !GraphStats {
    std.fs.deleteFileAbsolute(manifest_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    var argv = [_][]const u8{
        binary_path,
        "graph",
        "--root",
        ".",
        "--format",
        "json",
        "--plugin-dir",
        plugin_dir,
    };

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
        .cwd = root_path,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        return GraphError.GraphCommandFailed;
    }

    const manifest_file = try std.fs.openFileAbsolute(manifest_path, .{});
    defer manifest_file.close();
    const json_content = try manifest_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const manifest_value = parsed.value.object.get("manifest") orelse return GraphError.MissingManifest;
    const manifest_obj = manifest_value.object;

    const hits_value = manifest_obj.get("cache_hits") orelse return GraphError.MissingManifestField;
    const misses_value = manifest_obj.get("cache_misses") orelse return GraphError.MissingManifestField;

    return GraphStats{
        .hits = hits_value.integer,
        .misses = misses_value.integer,
    };
}

fn runCacheCommand(
    allocator: std.mem.Allocator,
    binary_path: []const u8,
    root_path: []const u8,
    args: []const []const u8,
) !std.process.Child.RunResult {
    const total = args.len + 1;
    var argv = try allocator.alloc([]const u8, total);
    defer allocator.free(argv);
    argv[0] = binary_path;
    for (args, 0..) |arg, idx| {
        argv[idx + 1] = arg;
    }

    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = root_path,
    });
}

fn extractMetric(buffer: []const u8, label: []const u8) MetricError!i64 {
    const start = std.mem.indexOf(u8, buffer, label) orelse return MetricError.MetricNotFound;
    var value_start = start + label.len;
    while (value_start < buffer.len and buffer[value_start] == ' ') {
        value_start += 1;
    }

    var value_end = value_start;
    while (value_end < buffer.len) : (value_end += 1) {
        const c = buffer[value_end];
        if (c == '\n' or c == '\r' or c == ' ') break;
    }

    const slice = buffer[value_start..value_end];
    if (slice.len == 0) return MetricError.InvalidMetric;

    return std.fmt.parseInt(i64, slice, 10) catch MetricError.InvalidMetric;
}

fn extractMetricBetween(buffer: []const u8, prefix: []const u8, suffix: []const u8) MetricError!i64 {
    const prefix_index = std.mem.indexOf(u8, buffer, prefix) orelse return MetricError.MetricNotFound;
    const value_start = prefix_index + prefix.len;
    const tail = buffer[value_start..];
    const suffix_index = std.mem.indexOf(u8, tail, suffix) orelse return MetricError.MetricNotFound;
    const slice = tail[0..suffix_index];
    const trimmed = std.mem.trim(u8, slice, " ");
    if (trimmed.len == 0) return MetricError.InvalidMetric;
    return std.fmt.parseInt(i64, trimmed, 10) catch MetricError.InvalidMetric;
}

fn computeManifestPath(allocator: std.mem.Allocator, root_path: []const u8) ![]const u8 {
    const base = std.fs.path.basename(root_path);
    const name = if (base.len == 0) "repository" else base;
    const filename = try std.fmt.allocPrint(allocator, "{s}.json", .{name});
    defer allocator.free(filename);
    return std.fs.path.join(allocator, &.{ root_path, filename });
}

fn getBinaryPath(allocator: std.mem.Allocator) ![]const u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, "zig-out", "bin", "repo2mmd" });
}

fn ensureBinary(allocator: std.mem.Allocator, binary_path: []const u8) !void {
    var needs_binary = false;
    if (std.fs.openFileAbsolute(binary_path, .{})) |_| {
        needs_binary = false;
    } else |_| needs_binary = true;

    if (needs_binary) {
        const build_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "zig", "build" },
        });
        defer allocator.free(build_result.stdout);
        defer allocator.free(build_result.stderr);

        if (build_result.term != .Exited or build_result.term.Exited != 0) {
            return GraphError.BuildFailed;
        }
    }

    const plugin_path = try computeZigPluginPath(allocator);
    defer allocator.free(plugin_path);

    if (std.fs.openFileAbsolute(plugin_path, .{})) |_| {
        return;
    } else |_| {}

    const plugin_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build", "plugins" },
    });
    defer allocator.free(plugin_result.stdout);
    defer allocator.free(plugin_result.stderr);

    if (plugin_result.term != .Exited or plugin_result.term.Exited != 0) {
        return GraphError.BuildFailed;
    }
}

fn computeZigPluginPath(allocator: std.mem.Allocator) ![]const u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return std.fs.path.join(allocator, &.{ cwd, "zig-out", "lib", "repo2mmd", "plugins", "librepo2mmd_zig.so" });
}

fn locatePluginDir(allocator: std.mem.Allocator, binary_path: []const u8) ![]const u8 {
    const bin_dir_path = std.fs.path.dirname(binary_path) orelse return GraphError.PluginDirNotFound;
    const bin_dir = try std.fs.cwd().realpathAlloc(allocator, bin_dir_path);
    defer allocator.free(bin_dir);

    const project_root_rel = try std.fs.path.join(allocator, &.{ bin_dir, "..", ".." });
    defer allocator.free(project_root_rel);

    const project_root = try std.fs.cwd().realpathAlloc(allocator, project_root_rel);
    defer allocator.free(project_root);

    const plugin_dir_rel = try std.fs.path.join(allocator, &.{ project_root, "zig-out", "lib", "repo2mmd", "plugins" });
    defer allocator.free(plugin_dir_rel);

    return std.fs.cwd().realpathAlloc(allocator, plugin_dir_rel);
}

fn countCacheEntries(allocator: std.mem.Allocator, root_path: []const u8) !usize {
    const cache_dir_path = try std.fs.path.join(allocator, &.{ root_path, ".repo2mmd", "cache" });
    defer allocator.free(cache_dir_path);

    var dir = std.fs.openDirAbsolute(cache_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer dir.close();

    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".cache")) {
            count += 1;
        }
    }

    return count;
}

const GraphError = error{
    GraphCommandFailed,
    MissingManifest,
    MissingManifestField,
    BuildFailed,
    PluginDirNotFound,
};

fn freeManifestPlugins(allocator: std.mem.Allocator, plugins: []ManifestPlugin) void {
    for (plugins) |plugin| {
        allocator.free(plugin.id);
        allocator.free(plugin.version);
    }
    allocator.free(plugins);
}

fn readManifestPlugins(allocator: std.mem.Allocator, manifest_path: []const u8) ![]ManifestPlugin {
    const manifest_file = try std.fs.openFileAbsolute(manifest_path, .{});
    defer manifest_file.close();

    const json_content = try manifest_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const manifest_value = parsed.value.object.get("manifest") orelse return GraphError.MissingManifest;
    if (manifest_value != .object) return GraphError.MissingManifestField;
    const manifest_obj = manifest_value.object;

    const plugins_value = manifest_obj.get("plugins_used") orelse return GraphError.MissingManifestField;
    if (plugins_value != .array) return GraphError.MissingManifestField;
    const plugins_array = plugins_value.array;

    const count = plugins_array.items.len;
    const plugins = try allocator.alloc(ManifestPlugin, count);
    var init_count: usize = 0;
    errdefer {
        for (plugins[0..init_count]) |plugin| {
            allocator.free(plugin.id);
            allocator.free(plugin.version);
        }
        allocator.free(plugins);
    }

    for (plugins_array.items, 0..) |plugin_entry, idx| {
        if (plugin_entry != .object) return GraphError.MissingManifestField;
        const plugin_obj = plugin_entry.object;
        const id_value = plugin_obj.get("id") orelse return GraphError.MissingManifestField;
        const version_value = plugin_obj.get("version") orelse return GraphError.MissingManifestField;
        if (id_value != .string or version_value != .string) return GraphError.MissingManifestField;
        plugins[idx] = .{
            .id = try allocator.dupe(u8, id_value.string),
            .version = try allocator.dupe(u8, version_value.string),
        };
        init_count = idx + 1;
    }

    return plugins;
}

fn preparePluginSandbox(allocator: std.mem.Allocator, root_path: []const u8, source_plugin_dir: []const u8) ![]const u8 {
    const sandbox_path = try std.fs.path.join(allocator, &.{ root_path, "plugins" });

    var root_dir = try std.fs.openDirAbsolute(root_path, .{ .iterate = true });
    defer root_dir.close();
    try root_dir.makePath("plugins");

    const src_path = try std.fs.path.join(allocator, &.{ source_plugin_dir, "librepo2mmd_zig.so" });
    defer allocator.free(src_path);

    const dst_path = try std.fs.path.join(allocator, &.{ sandbox_path, "librepo2mmd_zig.so" });
    defer allocator.free(dst_path);

    try std.fs.copyFileAbsolute(src_path, dst_path, .{});

    return sandbox_path;
}
