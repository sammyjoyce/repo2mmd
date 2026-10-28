const std = @import("std");
const cli = @import("../cli.zig");
const diag = @import("diag");
const cache = @import("cache_mgr");

pub fn executeCache(allocator: std.mem.Allocator, global_opts: cli.GlobalOptions, args: []const []const u8) !void {
    _ = global_opts;

    if (args.len == 0) {
        try printCacheHelp();
        return;
    }

    const subcommand = args[0];
    const sub_args = args[1..];

    if (std.mem.eql(u8, subcommand, "show")) {
        try runCacheShow(allocator, sub_args);
    } else if (std.mem.eql(u8, subcommand, "stats")) {
        try runCacheStats(allocator, sub_args);
    } else if (std.mem.eql(u8, subcommand, "prune")) {
        try runCachePrune(allocator, sub_args);
    } else if (std.mem.eql(u8, subcommand, "clear")) {
        try runCacheClear(allocator, sub_args);
    } else {
        try diag.printError("Unknown cache subcommand: {s}", .{subcommand});
        try printCacheHelp();
        return error.InvalidUsage;
    }
}

fn printCacheHelp() !void {
    try printOut(
        \\repo2mmd cache — Inspect or prune the analysis cache
        \\
        \\USAGE:
        \\  repo2mmd cache <show|stats|prune|clear> [OPTIONS]
        \\
        \\SUBCOMMANDS:
        \\  show                            # list cached artifacts
        \\  stats                           # size, entries, hit rate
        \\  prune                           # remove old/unused entries
        \\  clear                           # nuke the cache
        \\
        \\COMMON OPTIONS:
        \\      --older-than <dur>          # e.g., 7d, 4h (for prune/show)
        \\
        \\EXAMPLES:
        \\  repo2mmd cache stats
        \\  repo2mmd cache prune --older-than 7d
        \\  repo2mmd cache clear
        \\
    , .{});
}

fn runCacheShow(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;
    try diag.printError("Cache show command not yet implemented", .{});
    return error.NotImplemented;
}

fn runCacheStats(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    var cache_manager = cache.CacheManager.init(allocator) catch {
        return error.ExecutionFailed;
    };
    defer cache_manager.deinit();

    cache_manager.refreshEntryStats() catch {};
    const stats = cache_manager.getStats();

    try printOut("Cache Statistics:\n", .{});
    try printOut("  Entries: {d}\n", .{stats.entries});
    try printOut("  Total size: {d} bytes ({d:.1} MB)\n", .{ stats.total_size_bytes, @as(f64, @floatFromInt(stats.total_size_bytes)) / (1024.0 * 1024.0) });
    try printOut("  Cache hits: {d}\n", .{stats.hits});
    try printOut("  Cache misses: {d}\n", .{stats.misses});
    try printOut("  Hit rate: {d:.1}%\n", .{stats.hitRate()});
}

fn runCachePrune(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;
    try diag.printError("Cache prune command not yet implemented", .{});
    return error.NotImplemented;
}

fn runCacheClear(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    var cache_manager = cache.CacheManager.init(allocator) catch {
        return error.ExecutionFailed;
    };
    defer cache_manager.deinit();

    const result = cache_manager.clear() catch |err| {
        try diag.printError("Failed to clear cache: {s}", .{@errorName(err)});
        return error.ExecutionFailed;
    };

    try printOut("Cleared cache: removed {d} entries, freed {d} bytes ({d:.1} MB)\n", .{ result.removed_count, result.freed_bytes, @as(f64, @floatFromInt(result.freed_bytes)) / (1024.0 * 1024.0) });
}

fn printOut(comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(buffer[0..], fmt, args);
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(formatted);
}
