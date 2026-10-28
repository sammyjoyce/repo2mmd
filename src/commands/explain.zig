const std = @import("std");
const cli = @import("../cli.zig");
const diag = @import("diag");

const ExplainOptions = struct {
    format: ExplainFormat = .text,
    limit: ?u32 = null,
    show_evidence: bool = false,
};

const ExplainFormat = enum {
    text,
    json,

    pub fn parse(str: []const u8) ?@This() {
        if (std.mem.eql(u8, str, "text")) return .text;
        if (std.mem.eql(u8, str, "json")) return .json;
        return null;
    }
};

pub fn executeExplain(allocator: std.mem.Allocator, global_opts: cli.GlobalOptions, args: []const []const u8) !void {
    _ = global_opts;

    if (args.len == 0) {
        try printExplainHelp();
        return;
    }

    const explain_type = args[0];
    const explain_args = args[1..];

    if (std.mem.eql(u8, explain_type, "node")) {
        try runExplainNode(allocator, explain_args);
    } else if (std.mem.eql(u8, explain_type, "edge")) {
        try runExplainEdge(allocator, explain_args);
    } else {
        try diag.printError("Unknown explain type: {s}", .{explain_type});
        try printExplainHelp();
        return error.InvalidUsage;
    }
}

fn printExplainHelp() !void {
    try printOut(
        \\repo2mmd explain — Explain why a node or edge exists (experimental)
        \\
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

fn runExplainNode(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try diag.printError("Missing node ID", .{});
        return error.InvalidUsage;
    }

    var opts = ExplainOptions{};
    var node_id: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.startsWith(u8, arg, "-f") or std.mem.startsWith(u8, arg, "--format")) {
                const format_str = if (std.mem.startsWith(u8, arg, "--format="))
                    arg["--format=".len..]
                else if (std.mem.startsWith(u8, arg, "-f") and arg.len > 2)
                    arg[2..]
                else blk: {
                    if (i + 1 >= args.len) {
                        try diag.printError("Missing value for --format", .{});
                        return error.InvalidUsage;
                    }
                    i += 1;
                    break :blk args[i];
                };

                if (ExplainFormat.parse(format_str)) |fmt| {
                    opts.format = fmt;
                } else {
                    try diag.printError("Invalid format: {s}", .{format_str});
                    return error.InvalidUsage;
                }
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--limit=")) {
                const limit_str = arg["--limit=".len..];
                opts.limit = std.fmt.parseInt(u32, limit_str, 10) catch |err| switch (err) {
                    error.InvalidCharacter => {
                        try diag.printError("Invalid limit value: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                    error.Overflow => {
                        try diag.printError("Limit value too large: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                };
                continue;
            }

            if (std.mem.eql(u8, arg, "--limit")) {
                if (i + 1 >= args.len) {
                    try diag.printError("Missing value for --limit", .{});
                    return error.InvalidUsage;
                }
                i += 1;
                const limit_str = args[i];
                opts.limit = std.fmt.parseInt(u32, limit_str, 10) catch |err| switch (err) {
                    error.InvalidCharacter => {
                        try diag.printError("Invalid limit value: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                    error.Overflow => {
                        try diag.printError("Limit value too large: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                };
                continue;
            }

            if (std.mem.eql(u8, arg, "--show-evidence")) {
                opts.show_evidence = true;
                continue;
            }

            try diag.printError("Unknown option: {s}", .{arg});
            return error.InvalidUsage;
        } else {
            // Positional argument - node ID
            if (node_id != null) {
                try diag.printError("Multiple node IDs specified", .{});
                return error.InvalidUsage;
            }
            node_id = arg;
        }
    }

    if (node_id == null) {
        try diag.printError("Missing node ID", .{});
        return error.InvalidUsage;
    }

    try explainNode(allocator, node_id.?, opts);
}

fn runExplainEdge(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        try diag.printError("Missing source and destination node IDs", .{});
        return error.InvalidUsage;
    }

    var opts = ExplainOptions{};
    var src_id: ?[]const u8 = null;
    var dst_id: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.startsWith(u8, arg, "-f") or std.mem.startsWith(u8, arg, "--format")) {
                const format_str = if (std.mem.startsWith(u8, arg, "--format="))
                    arg["--format=".len..]
                else if (std.mem.startsWith(u8, arg, "-f") and arg.len > 2)
                    arg[2..]
                else blk: {
                    if (i + 1 >= args.len) {
                        try diag.printError("Missing value for --format", .{});
                        return error.InvalidUsage;
                    }
                    i += 1;
                    break :blk args[i];
                };

                if (ExplainFormat.parse(format_str)) |fmt| {
                    opts.format = fmt;
                } else {
                    try diag.printError("Invalid format: {s}", .{format_str});
                    return error.InvalidUsage;
                }
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--limit=")) {
                const limit_str = arg["--limit=".len..];
                opts.limit = std.fmt.parseInt(u32, limit_str, 10) catch |err| switch (err) {
                    error.InvalidCharacter => {
                        try diag.printError("Invalid limit value: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                    error.Overflow => {
                        try diag.printError("Limit value too large: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                };
                continue;
            }

            if (std.mem.eql(u8, arg, "--limit")) {
                if (i + 1 >= args.len) {
                    try diag.printError("Missing value for --limit", .{});
                    return error.InvalidUsage;
                }
                i += 1;
                const limit_str = args[i];
                opts.limit = std.fmt.parseInt(u32, limit_str, 10) catch |err| switch (err) {
                    error.InvalidCharacter => {
                        try diag.printError("Invalid limit value: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                    error.Overflow => {
                        try diag.printError("Limit value too large: {s}", .{limit_str});
                        return error.InvalidUsage;
                    },
                };
                continue;
            }

            if (std.mem.eql(u8, arg, "--show-evidence")) {
                opts.show_evidence = true;
                continue;
            }

            try diag.printError("Unknown option: {s}", .{arg});
            return error.InvalidUsage;
        } else {
            // Positional arguments - source and destination IDs
            if (src_id == null) {
                src_id = arg;
            } else if (dst_id == null) {
                dst_id = arg;
            } else {
                try diag.printError("Too many arguments for edge explanation", .{});
                return error.InvalidUsage;
            }
        }
    }

    if (src_id == null or dst_id == null) {
        try diag.printError("Missing source or destination node ID", .{});
        return error.InvalidUsage;
    }

    try explainEdge(allocator, src_id.?, dst_id.?, opts);
}

fn explainNode(allocator: std.mem.Allocator, node_id: []const u8, opts: ExplainOptions) !void {
    _ = allocator;
    _ = node_id;
    _ = opts;
    try diag.printError("Node explanation not yet implemented", .{});
    return error.NotImplemented;
}

fn explainEdge(allocator: std.mem.Allocator, src_id: []const u8, dst_id: []const u8, opts: ExplainOptions) !void {
    _ = allocator;
    _ = src_id;
    _ = dst_id;
    _ = opts;
    try diag.printError("Edge explanation not yet implemented", .{});
    return error.NotImplemented;
}

fn printOut(comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(buffer[0..], fmt, args);
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(formatted);
}
