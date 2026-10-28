const std = @import("std");
const cli = @import("../cli.zig");
const diag = @import("diag");
const path_resolver = @import("path_resolver");

pub fn executeConfig(allocator: std.mem.Allocator, global_opts: cli.GlobalOptions, args: []const []const u8) !void {
    _ = global_opts;

    if (args.len == 0) {
        try printConfigHelp();
        return;
    }

    const subcommand = args[0];
    const sub_args = args[1..];

    if (std.mem.eql(u8, subcommand, "paths")) {
        try runConfigPaths(allocator, sub_args);
    } else if (std.mem.eql(u8, subcommand, "init")) {
        try runConfigInit(allocator, sub_args);
    } else if (std.mem.eql(u8, subcommand, "show")) {
        try runConfigShow(allocator, sub_args);
    } else {
        try diag.printError("Unknown config subcommand: {s}", .{subcommand});
        try printConfigHelp();
        return error.InvalidUsage;
    }
}

fn printConfigHelp() !void {
    try printOut(
        \\repo2mmd config — Configuration utilities
        \\
        \\USAGE:
        \\  repo2mmd config <paths|init|show>
        \\
        \\SUBCOMMANDS:
        \\  paths                           # show XDG-aware directories (cache, config, data, plugins)
        \\  init                            # write a starter repo2mmd.toml to the current dir
        \\  show                            # display the effective configuration
        \\
        \\EXAMPLES:
        \\  repo2mmd config paths
        \\  repo2mmd config init
        \\  repo2mmd config show
        \\
    , .{});
}

fn runConfigPaths(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0) {
        try diag.printError("paths subcommand does not accept additional arguments", .{});
        return error.InvalidUsage;
    }

    const options = path_resolver.Options{};

    const cache_dir = blk: {
        break :blk path_resolver.getCacheDir(allocator, options) catch |err| switch (err) {
            error.MissingHome => allocator.dupe(u8, "<unavailable>") catch return error.ExecutionFailed,
            error.OutOfMemory => return error.ExecutionFailed,
            else => {
                try diag.printError("Failed to resolve cache directory: {s}", .{@errorName(err)});
                return error.ExecutionFailed;
            },
        };
    };
    defer allocator.free(cache_dir);

    const config_dir = blk: {
        break :blk path_resolver.getConfigDir(allocator, options) catch |err| switch (err) {
            error.MissingHome => allocator.dupe(u8, "<unavailable>") catch return error.ExecutionFailed,
            error.OutOfMemory => return error.ExecutionFailed,
            else => {
                try diag.printError("Failed to resolve config directory: {s}", .{@errorName(err)});
                return error.ExecutionFailed;
            },
        };
    };
    defer allocator.free(config_dir);

    const data_dir = blk: {
        break :blk path_resolver.getDataDir(allocator, options) catch |err| switch (err) {
            error.MissingHome => allocator.dupe(u8, "<unavailable>") catch return error.ExecutionFailed,
            error.OutOfMemory => return error.ExecutionFailed,
            else => {
                try diag.printError("Failed to resolve data directory: {s}", .{@errorName(err)});
                return error.ExecutionFailed;
            },
        };
    };
    defer allocator.free(data_dir);

    var plugin_dirs_owned = false;
    const plugin_dirs: [][]u8 = blk: {
        const dirs = path_resolver.getPluginDirs(allocator, options) catch |err| switch (err) {
            error.MissingHome => break :blk &.{},
            error.OutOfMemory => {
                try diag.printError("Failed to resolve plugin directories: {s}", .{@errorName(err)});
                return error.ExecutionFailed;
            },
            else => {
                try diag.printError("Failed to resolve plugin directories: {s}", .{@errorName(err)});
                return error.ExecutionFailed;
            },
        };
        plugin_dirs_owned = true;
        break :blk dirs;
    };
    defer if (plugin_dirs_owned) path_resolver.freeDirList(allocator, plugin_dirs);

    try printOut("XDG-aware directories:\n", .{});
    try printOut("  cache: {s}\n", .{cache_dir});
    try printOut("  config: {s}\n", .{config_dir});
    try printOut("  data: {s}\n", .{data_dir});

    if (plugin_dirs.len == 0) {
        try printOut("  plugins: (none)\n", .{});
    } else {
        try printOut("  plugins:\n", .{});
        for (plugin_dirs) |dir| {
            try printOut("    - {s}\n", .{dir});
        }
    }
}

fn runConfigInit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    if (args.len > 0) {
        try diag.printError("init subcommand does not accept additional arguments", .{});
        return error.InvalidUsage;
    }

    const config_content =
        \\# repo2mmd Configuration File
        \\# Generated automatically
        \\
        \\[analysis]
        \\# Root directory to analyze (default: current directory)
        \\# root = "."
        \\
        \\# File patterns to include
        \\include_patterns = [
        \\    "**/*.zig",
        \\    "**/*.c",
        \\    "**/*.h",
        \\]
        \\
        \\[output]
        \\# Default output format: mmd, json
        \\default_format = "mmd"
        \\
        \\[cache]
        \\# Cache mode: rw, ro, off
        \\mode = "rw"
        \\
    ;

    const output_path = "repo2mmd.toml";
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(config_content);

    try diag.printOk("Configuration file created: {s}", .{output_path});
}

fn runConfigShow(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;
    try diag.printError("Config show command not yet implemented", .{});
    return error.NotImplemented;
}

fn printOut(comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(buffer[0..], fmt, args);
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(formatted);
}
