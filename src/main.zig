const std = @import("std");
const cli = @import("cli.zig");
const help = @import("help.zig");
const path_resolver = @import("path_resolver");
const diag = @import("diag");

const CommandError = error{
    InvalidUsage,
    ExecutionFailed,
} || anyerror;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leak_result = gpa.deinit();
        if (@import("builtin").mode == .Debug and leak_result == .leak) {
            std.debug.print("Memory leaks detected!\n", .{});
            std.process.exit(1);
        }
    }

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize path resolver and handle migration
    const resolver_options = path_resolver.Options{};
    const cache_dir = try path_resolver.getCacheDir(std.heap.page_allocator, resolver_options);
    defer std.heap.page_allocator.free(cache_dir);

    const config_dir = try path_resolver.getConfigDir(std.heap.page_allocator, resolver_options);
    defer std.heap.page_allocator.free(config_dir);

    const data_dir = try path_resolver.getDataDir(std.heap.page_allocator, resolver_options);
    defer std.heap.page_allocator.free(data_dir);

    const plugin_dirs = try path_resolver.getPluginDirs(std.heap.page_allocator, resolver_options);
    defer path_resolver.freeDirList(std.heap.page_allocator, plugin_dirs);

    var migration_options = resolver_options;
    migration_options.legacy_root = ".repo2mmd";

    const migration = path_resolver.migrateLegacyPaths(
        std.heap.page_allocator,
        migration_options,
        .{
            .cache_dir = cache_dir,
            .config_dir = config_dir,
            .data_dir = data_dir,
            .plugin_dirs = plugin_dirs,
        },
    ) catch |err| switch (err) {
        error.MissingHome => path_resolver.MigrationResult{},
        else => return err,
    };

    if (migration.cache_migrated or migration.data_migrated or migration.plugins_migrated or migration.config_migrated) {
        try diag.printOk(
            "Migrated legacy .repo2mmd directories (cache={s}, data={s}, plugins={s}, config={s})",
            .{
                if (migration.cache_migrated) "moved" else "unchanged",
                if (migration.data_migrated) "moved" else "unchanged",
                if (migration.plugins_migrated) "moved" else "unchanged",
                if (migration.config_migrated) "moved" else "unchanged",
            },
        );
    }

    // Handle empty args
    if (args.len <= 1) {
        try help.printTopLevelHelp(cli.CommandRegistry.init());
        return;
    }

    // Parse global options from args
    const global_opts_and_remaining = try cli.ArgParser.parseGlobalOptions(allocator, args[1..]);
    var global_opts = global_opts_and_remaining[0];
    defer global_opts.deinit(allocator);
    const global_opts_parsed_count = global_opts_and_remaining[1];

    // Handle global flags that don't require command execution
    if (global_opts.show_help) {
        try help.printTopLevelHelp(cli.CommandRegistry.init());
        return;
    }

    if (global_opts.show_version) {
        try help.printVersion();
        return;
    }

    // Determine command and remaining args
    const remaining_args = args[1 + global_opts_parsed_count ..];

    if (remaining_args.len == 0) {
        // Default to generate command with current directory
        try executeDefaultCommand(allocator, global_opts);
        return;
    }

    const first_arg = remaining_args[0];
    const command_args = remaining_args[1..];

    // Check if this is a command
    const registry = cli.CommandRegistry.init();
    if (registry.find(first_arg)) |cmd| {
        // Handle command-specific help
        if (command_args.len > 0 and cli.ArgParser.isHelpFlag(command_args[0])) {
            try help.printCommandHelp(cmd);
            return;
        }

        // Execute the command
        cmd.execute(allocator, global_opts, command_args) catch |err| switch (err) {
            error.InvalidUsage, error.InvalidArgument => {
                try help.printCommandHelp(cmd);
                std.process.exit(2);
            },
            error.ExecutionFailed, error.NoFilesFound => std.process.exit(1),
            else => return err,
        };
        return;
    }

    // If not a command, treat as default generate command with path
    try executeDefaultCommandWithPath(allocator, global_opts, remaining_args);
}

fn executeDefaultCommand(allocator: std.mem.Allocator, global_opts: cli.GlobalOptions) !void {
    // Default: generate command with current directory
    const generate = @import("commands/generate.zig");
    generate.executeGenerate(allocator, global_opts, &[_][]const u8{}) catch |err| switch (err) {
        error.InvalidArgument => {
            try help.printCommandHelp(cli.CommandRegistry.init().find("generate").?);
            std.process.exit(2);
        },
        error.NoFilesFound => {
            try diag.printError("No files found to process", .{});
            std.process.exit(1);
        },
        else => return err,
    };
}

fn executeDefaultCommandWithPath(allocator: std.mem.Allocator, global_opts: cli.GlobalOptions, path_args: []const []const u8) !void {
    // Default: generate command with specified path(s)
    const generate = @import("commands/generate.zig");
    generate.executeGenerate(allocator, global_opts, path_args) catch |err| switch (err) {
        error.InvalidArgument => {
            try help.printCommandHelp(cli.CommandRegistry.init().find("generate").?);
            std.process.exit(2);
        },
        error.NoFilesFound => {
            try diag.printError("No files found to process", .{});
            std.process.exit(1);
        },
        else => return err,
    };
}
