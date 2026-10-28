const std = @import("std");
const diag = @import("diag");

/// Global options that apply to all commands
pub const GlobalOptions = struct {
    quiet: bool = false,
    verbose: u8 = 0,
    log_level: LogLevel = .info,
    color: ColorMode = .auto,
    config_file: ?[]const u8 = null,
    cache_mode: CacheMode = .rw,
    plugin_dirs: std.ArrayList([]const u8),
    show_help: bool = false,
    show_version: bool = false,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.plugin_dirs.deinit(allocator);
    }
};

pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,

    pub fn parse(str: []const u8) ?@This() {
        if (std.mem.eql(u8, str, "trace")) return .trace;
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "warn")) return .warn;
        if (std.mem.eql(u8, str, "error")) return .err;
        return null;
    }
};

pub const ColorMode = enum {
    auto,
    always,
    never,

    pub fn parse(str: []const u8) ?@This() {
        if (std.mem.eql(u8, str, "auto")) return .auto;
        if (std.mem.eql(u8, str, "always")) return .always;
        if (std.mem.eql(u8, str, "never")) return .never;
        return null;
    }
};

pub const CacheMode = enum {
    rw,
    ro,
    off,

    pub fn parse(str: []const u8) ?@This() {
        if (std.mem.eql(u8, str, "rw")) return .rw;
        if (std.mem.eql(u8, str, "ro")) return .ro;
        if (std.mem.eql(u8, str, "off")) return .off;
        return null;
    }
};

/// Command definition and execution interface
pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    help: []const u8,
    execute: *const fn (allocator: std.mem.Allocator, global_opts: GlobalOptions, args: []const []const u8) anyerror!void,
};

/// Registry of all available commands
pub const CommandRegistry = struct {
    commands: []const Command,

    pub fn init() @This() {
        return @This(){
            .commands = &[_]Command{
                commands.generate,
                commands.analyze,
                commands.render,
                commands.explain,
                commands.cache,
                commands.config,
            },
        };
    }

    pub fn find(self: @This(), name: []const u8) ?Command {
        for (self.commands) |cmd| {
            if (std.mem.eql(u8, cmd.name, name)) {
                return cmd;
            }
        }
        return null;
    }

    pub fn list(self: @This()) []const Command {
        return self.commands;
    }
};

/// Command implementations
const commands = struct {
    pub const generate = Command{
        .name = "generate",
        .summary = "Analyze PATH and emit a diagram (default; alias: graph)",
        .help =
        \\Analyze a repository path and generate a Mermaid diagram by default.
        \\
        \\This is the default command - running 'repo2mmd [PATH]' is equivalent
        \\to 'repo2mmd generate [PATH]'.
        \\
        \\The output format can be inferred from the --output file extension:
        \\  .mmd  -> Mermaid diagram (default)
        \\  .json -> Graph JSON
        \\
        \\If no --output is specified, writes to stdout.
        ,
        .execute = executeGenerate,
    };

    pub const analyze = Command{
        .name = "analyze",
        .summary = "Analyze PATH and emit graph JSON",
        .help =
        \\Analyze a repository path and emit machine-readable graph JSON.
        \\
        \\This command performs the same analysis as 'generate' but outputs
        \\the raw graph data in JSON format instead of a rendered diagram.
        \\
        \\Use this when you want to:
        \\  - Process the graph data programmatically
        \\  - Store analysis results for later processing
        \\  - Use the 'render' command to generate different output formats
        ,
        .execute = executeAnalyze,
    };

    pub const render = Command{
        .name = "render",
        .summary = "Render a graph JSON to Mermaid",
        .help =
        \\Render a graph JSON file to a Mermaid diagram.
        \\
        \\This command takes graph JSON (produced by 'analyze') and renders
        \\it to various output formats. Currently supports Mermaid diagrams,
        \\with plans for additional formats like Graphviz DOT.
        \\
        \\Input can be a file path or '-' for stdin.
        ,
        .execute = executeRender,
    };

    pub const explain = Command{
        .name = "explain",
        .summary = "Explain why a node or edge exists (experimental)",
        .help =
        \\Explain the evidence and reasoning behind a specific node or edge.
        \\
        \\This command provides detailed information about why repo2mmd
        \\identified a particular node or created a specific edge, including
        \\source locations and certainty scores.
        \\
        \\USAGE:
        \\  repo2mmd explain node <NODE_ID>
        \\  repo2mmd explain edge <SRC_ID> <DST_ID>
        ,
        .execute = executeExplain,
    };

    pub const cache = Command{
        .name = "cache",
        .summary = "Inspect or prune the analysis cache",
        .help =
        \\Manage repo2mmd's content-addressed analysis cache.
        \\
        \\The cache stores analysis results to speed up subsequent runs.
        \\This command provides utilities to inspect, manage, and clean the cache.
        \\
        \\SUBCOMMANDS:
        \\  show    List cached artifacts
        \\  stats   Show cache statistics and hit rates
        \\  prune   Remove old/unused entries
        \\  clear   Remove all cache entries
        ,
        .execute = executeCache,
    };

    pub const config = Command{
        .name = "config",
        .summary = "Show or initialize configuration",
        .help =
        \\Configuration utilities for repo2mmd.
        \\
        \\SUBCOMMANDS:
        \\  paths  Show XDG-aware directories (cache, config, data, plugins)
        \\  init   Write a starter repo2mmd.toml to the current directory
        \\  show   Display the effective configuration
        ,
        .execute = executeConfig,
    };
};

// Command execution functions - implemented in separate files
fn executeGenerate(allocator: std.mem.Allocator, global_opts: GlobalOptions, args: []const []const u8) !void {
    const generate = @import("commands/generate.zig");
    return generate.executeGenerate(allocator, global_opts, args);
}

fn executeAnalyze(allocator: std.mem.Allocator, global_opts: GlobalOptions, args: []const []const u8) !void {
    const analyze = @import("commands/analyze.zig");
    return analyze.executeAnalyze(allocator, global_opts, args);
}

fn executeRender(allocator: std.mem.Allocator, global_opts: GlobalOptions, args: []const []const u8) !void {
    const render = @import("commands/render.zig");
    return render.executeRender(allocator, global_opts, args);
}

fn executeExplain(allocator: std.mem.Allocator, global_opts: GlobalOptions, args: []const []const u8) !void {
    const explain = @import("commands/explain.zig");
    return explain.executeExplain(allocator, global_opts, args);
}

fn executeCache(allocator: std.mem.Allocator, global_opts: GlobalOptions, args: []const []const u8) !void {
    const cache = @import("commands/cache_cmd.zig");
    return cache.executeCache(allocator, global_opts, args);
}

fn executeConfig(allocator: std.mem.Allocator, global_opts: GlobalOptions, args: []const []const u8) !void {
    const config = @import("commands/config.zig");
    return config.executeConfig(allocator, global_opts, args);
}

/// Argument parsing utilities
pub const ArgParser = struct {
    pub fn parseGlobalOptions(allocator: std.mem.Allocator, args: []const []const u8) !struct { GlobalOptions, usize } {
        var global_opts = GlobalOptions{
            .plugin_dirs = std.ArrayList([]const u8).initCapacity(allocator, 0) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            },
        };
        var i: usize = 0;

        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (isHelpFlag(arg)) {
                global_opts.show_help = true;
                continue;
            }

            if (isVersionFlag(arg)) {
                global_opts.show_version = true;
                continue;
            }

            if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
                global_opts.quiet = true;
                continue;
            }

            if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
                global_opts.verbose += 1;
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--log-level=")) {
                const value = arg["--log-level=".len..];
                if (LogLevel.parse(value)) |level| {
                    global_opts.log_level = level;
                } else {
                    try diag.printError("Invalid log level: {s}", .{value});
                    return error.InvalidUsage;
                }
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--color=")) {
                const value = arg["--color=".len..];
                if (ColorMode.parse(value)) |mode| {
                    global_opts.color = mode;
                } else {
                    try diag.printError("Invalid color mode: {s}", .{value});
                    return error.InvalidUsage;
                }
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--config=")) {
                const value = arg["--config=".len..];
                if (value.len == 0) {
                    try diag.printError("Missing value for --config", .{});
                    return error.InvalidUsage;
                }
                global_opts.config_file = value;
                continue;
            }

            if (std.mem.eql(u8, arg, "--config")) {
                if (i + 1 >= args.len) {
                    try diag.printError("Missing value for --config", .{});
                    return error.InvalidUsage;
                }
                i += 1;
                global_opts.config_file = args[i];
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--cache-mode=")) {
                const value = arg["--cache-mode=".len..];
                if (CacheMode.parse(value)) |mode| {
                    global_opts.cache_mode = mode;
                } else {
                    try diag.printError("Invalid cache mode: {s}", .{value});
                    return error.InvalidUsage;
                }
                continue;
            }

            if (std.mem.eql(u8, arg, "--cache-mode")) {
                if (i + 1 >= args.len) {
                    try diag.printError("Missing value for --cache-mode", .{});
                    return error.InvalidUsage;
                }
                i += 1;
                if (CacheMode.parse(args[i])) |mode| {
                    global_opts.cache_mode = mode;
                } else {
                    try diag.printError("Invalid cache mode: {s}", .{args[i]});
                    return error.InvalidUsage;
                }
                continue;
            }

            if (std.mem.eql(u8, arg, "--no-cache")) {
                global_opts.cache_mode = .off;
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--plugin-dir=")) {
                const value = arg["--plugin-dir=".len..];
                if (value.len == 0) {
                    try diag.printError("Missing value for --plugin-dir", .{});
                    return error.InvalidUsage;
                }
                try global_opts.plugin_dirs.append(allocator, value);
                continue;
            }

            if (std.mem.eql(u8, arg, "--plugin-dir")) {
                if (i + 1 >= args.len) {
                    try diag.printError("Missing value for --plugin-dir", .{});
                    return error.InvalidUsage;
                }
                i += 1;
                try global_opts.plugin_dirs.append(allocator, args[i]);
                continue;
            }

            // If we get here, this is not a global option
            break;
        }

        return .{ global_opts, i };
    }

    pub fn isHelpFlag(value: []const u8) bool {
        return std.mem.eql(u8, value, "--help") or std.mem.eql(u8, value, "-h");
    }

    pub fn isVersionFlag(value: []const u8) bool {
        return std.mem.eql(u8, value, "--version") or std.mem.eql(u8, value, "-V");
    }
};

/// Format inference utilities
pub const FormatInference = struct {
    pub const OutputFormat = enum {
        mmd,
        json,

        pub fn parse(str: []const u8) ?@This() {
            if (std.mem.eql(u8, str, "mmd")) return .mmd;
            if (std.mem.eql(u8, str, "mermaid")) return .mmd;
            if (std.mem.eql(u8, str, "json")) return .json;
            if (std.mem.eql(u8, str, "text")) return .mmd; // legacy alias
            return null;
        }

        pub fn fromFilePath(path: []const u8) ?@This() {
            const ext = std.fs.path.extension(path);
            if (std.mem.eql(u8, ext, ".mmd")) return .mmd;
            if (std.mem.eql(u8, ext, ".json")) return .json;
            return null;
        }
    };
};
