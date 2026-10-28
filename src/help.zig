const std = @import("std");
const cli = @import("cli.zig");
const diag = @import("diag");

pub fn printTopLevelHelp(registry: cli.CommandRegistry) !void {
    try printOut(
        \\repo2mmd — Repository → Mermaid diagram generator
        \\
        \\USAGE:
        \\  repo2mmd [OPTIONS] [PATH]                # generate Mermaid to stdout (default)
        \\  repo2mmd <command> [<args>...]
        \\
        \\DESCRIPTION:
        \\  Scan repositories and emit Mermaid diagrams that reflect code structure 
        \\  with certainty tags.
        \\
        \\COMMANDS:
        \\
    , .{});

    for (registry.list()) |cmd| {
        try printOut("  {s:<12} {s}\n", .{ cmd.name, cmd.summary });
    }

    try printOut(
        \\
        \\GLOBAL OPTIONS:
        \\  -q, --quiet
        \\  -v, --verbose                    # repeat for more verbosity
        \\      --log-level <trace|debug|info|warn|error>
        \\      --color <auto|always|never>
        \\      --config <file>
        \\      --cache-mode <rw|ro|off>     # alias: --no-cache  -> off
        \\      --plugin-dir <dir>           # repeatable; searched in order
        \\      --version
        \\      --help
        \\
        \\EXAMPLES:
        \\  repo2mmd                         # Mermaid to stdout for the current directory
        \\  repo2mmd . -o repo.mmd          # Write Mermaid to a file
        \\  repo2mmd src --format json      # Emit graph JSON instead of Mermaid
        \\  repo2mmd analyze . -o graph.json
        \\  repo2mmd render graph.json -o repo.mmd
        \\
        \\Run `repo2mmd <command> --help` for command-specific help.
        \\For more information, visit: https://github.com/sammyjoyce/repo2mmd
        \\To generate OpenCLI specification: zig build opencli
        \\
    , .{});
}

pub fn printCommandHelp(cmd: cli.Command) !void {
    try printOut(
        \\repo2mmd {s} — {s}
        \\
        \\USAGE:
        \\  repo2mmd {s} [OPTIONS]
        \\
        \\DESCRIPTION:
        \\  {s}
        \\
    , .{ cmd.name, cmd.summary, cmd.name, cmd.help });

    // Command-specific options and examples
    if (std.mem.eql(u8, cmd.name, "generate")) {
        try printOut(
            \\OPTIONS:
            \\  -o, --output <file>             # default: stdout
            \\  -f, --format <mmd|json>         # default: mmd; inferred from --output extension
            \\  -j, --jobs <n>
            \\      --include <glob>            # repeatable
            \\      --exclude <glob>            # repeatable
            \\      --lang <list>               # e.g., go,ts,py
            \\      --certainty-threshold <0..1>
            \\      --[no-]respect-gitignore
            \\      --plugin-dir <dir>          # repeatable
            \\
            \\EXAMPLES:
            \\  repo2mmd generate .                       # Mermaid to stdout
            \\  repo2mmd generate src -o repo.mmd
            \\  repo2mmd generate --format json -o graph.json
            \\
        , .{});
    }

    if (std.mem.eql(u8, cmd.name, "analyze")) {
        try printOut(
            \\OPTIONS:
            \\  -o, --output <file>             # default: stdout
            \\  -j, --jobs <n>
            \\      --include <glob>            # repeatable
            \\      --exclude <glob>            # repeatable
            \\      --lang <list>               # e.g., go,ts,py
            \\      --plugin-dir <dir>          # repeatable
            \\
            \\EXAMPLES:
            \\  repo2mmd analyze . -o graph.json
            \\  repo2mmd analyze src --output analysis.json
            \\
        , .{});
    }

    if (std.mem.eql(u8, cmd.name, "render")) {
        try printOut(
            \\OPTIONS:
            \\  -o, --output <file>             # default: stdout
            \\  -f, --format <mmd>              # future: dot|plantuml
            \\      --style key=value           # repeatable; passes theme/style hints
            \\
            \\EXAMPLES:
            \\  repo2mmd render graph.json -o repo.mmd
            \\  cat graph.json | repo2mmd render -o repo.mmd
            \\
        , .{});
    }

    if (std.mem.eql(u8, cmd.name, "cache")) {
        try printOut(
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

    if (std.mem.eql(u8, cmd.name, "config")) {
        try printOut(
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

    if (std.mem.eql(u8, cmd.name, "explain")) {
        try printOut(
            \\USAGE:
            \\  repo2mmd explain node <ID>
            \\  repo2mmd explain edge <SRC> <DST>
            \\
            \\OPTIONS:
            \\  -f, --format <text|json>        # default: text
            \\      --limit <n>                 # limit evidence output
            \\      --show-evidence             # include source evidence
            \\
            \\EXAMPLES:
            \\  repo2mmd explain node src/main.zig:42
            \\  repo2mmd explain edge node1 node2 --format json
            \\
        , .{});
    }

    try printOut("For more information, visit: https://github.com/sammyjoyce/repo2mmd\n", .{});
}

pub fn printVersion() !void {
    try printOut("repo2mmd {s}\n", .{@import("build_options").version});
}

fn printOut(comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(buffer[0..], fmt, args);
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(formatted);
}
