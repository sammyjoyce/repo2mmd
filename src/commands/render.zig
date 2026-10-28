const std = @import("std");
const cli = @import("../cli.zig");
const diag = @import("diag");
const ir = @import("ir");
const mermaid_emitter = @import("mermaid_emitter");
const json_emitter = @import("json_emitter");

const RenderOptions = struct {
    output: ?[]const u8 = null,
    format: cli.FormatInference.OutputFormat = .mmd,
    styles: std.ArrayList([]const u8),

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.styles.deinit(allocator);
    }
};

pub fn executeRender(allocator: std.mem.Allocator, global_opts: cli.GlobalOptions, args: []const []const u8) !void {
    var opts = RenderOptions{
        .styles = std.ArrayList([]const u8).initCapacity(allocator, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        },
    };
    defer opts.deinit(allocator);

    var input_arg: ?[]const u8 = null;

    // Parse command-specific arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "-")) {
            // Handle flags
            if (std.mem.startsWith(u8, arg, "-o") or std.mem.startsWith(u8, arg, "--output")) {
                if (std.mem.startsWith(u8, arg, "--output=")) {
                    opts.output = arg["--output=".len..];
                } else if (std.mem.startsWith(u8, arg, "-o")) {
                    if (arg.len > 2) {
                        opts.output = arg[2..];
                    } else {
                        if (i + 1 >= args.len) {
                            try diag.printError("Missing value for --output", .{});
                            return error.InvalidUsage;
                        }
                        i += 1;
                        opts.output = args[i];
                    }
                } else {
                    if (i + 1 >= args.len) {
                        try diag.printError("Missing value for --output", .{});
                        return error.InvalidUsage;
                    }
                    i += 1;
                    opts.output = args[i];
                }
                continue;
            }

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

                if (cli.FormatInference.OutputFormat.parse(format_str)) |fmt| {
                    opts.format = fmt;
                } else {
                    try diag.printError("Invalid format: {s}", .{format_str});
                    return error.InvalidUsage;
                }
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--style=")) {
                try opts.styles.append(allocator, arg["--style=".len..]);
                continue;
            }

            if (std.mem.eql(u8, arg, "--style")) {
                if (i + 1 >= args.len) {
                    try diag.printError("Missing value for --style", .{});
                    return error.InvalidUsage;
                }
                i += 1;
                try opts.styles.append(allocator, args[i]);
                continue;
            }

            try diag.printError("Unknown option: {s}", .{arg});
            return error.InvalidUsage;
        } else {
            // Positional argument - input file
            if (input_arg != null) {
                try diag.printError("Multiple input files specified", .{});
                return error.InvalidUsage;
            }
            input_arg = arg;
        }
    }

    // Require input file
    if (input_arg == null) {
        try diag.printError("Missing input file", .{});
        return error.InvalidUsage;
    }

    // Determine output destination (default to stdout)
    const output_dest = opts.output orelse "-";

    // Execute the rendering
    try runRender(allocator, global_opts, input_arg.?, output_dest, opts);
}

fn runRender(
    allocator: std.mem.Allocator,
    global_opts: cli.GlobalOptions,
    input_path: []const u8,
    output_dest: []const u8,
    opts: RenderOptions,
) !void {
    // Apply global options
    if (global_opts.quiet) {
        // TODO: Implement quiet mode
    }

    // TODO: Apply style options from opts

    // Read input JSON
    const json_content = if (std.mem.eql(u8, input_path, "-"))
        try readAllStdin(allocator)
    else
        try std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024 * 10); // 10MB limit
    defer allocator.free(json_content);

    // Parse JSON to IR
    const parsed = try std.json.parseFromSliceLeaky(ir.IR, allocator, json_content, .{});

    // Render based on format
    switch (opts.format) {
        .mmd => try renderMermaid(allocator, parsed, output_dest),
        .json => try renderJson(allocator, parsed, output_dest),
    }
}

fn readAllStdin(allocator: std.mem.Allocator) ![]u8 {
    const stdin = std.fs.File.stdin();
    const size = try stdin.getEndPos();
    const buffer = try allocator.alloc(u8, @intCast(size));
    const bytes_read = try stdin.readAll(buffer);
    if (bytes_read != size) {
        allocator.free(buffer);
        return error.UnexpectedEOF;
    }
    return buffer;
}

fn renderMermaid(allocator: std.mem.Allocator, ir_data: ir.IR, output_path: []const u8) !void {
    const file = if (std.mem.eql(u8, output_path, "-"))
        std.fs.File.stdout()
    else
        try std.fs.cwd().createFile(output_path, .{});
    defer if (!std.mem.eql(u8, output_path, "-")) file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll("```mermaid\n");

    var flowchart = mermaid_emitter.MermaidFlowchartEmitter(@TypeOf(writer)).init(allocator, &writer);
    try flowchart.emit(ir_data.graph, "Repository Dependencies");

    try writer.interface.writeAll("```\n");
    try writer.interface.flush();

    const output_desc = if (std.mem.eql(u8, output_path, "-")) "stdout" else output_path;
    try diag.printOk("Mermaid diagram rendered to {s} ({d} nodes, {d} edges)", .{ output_desc, ir_data.graph.nodes.len, ir_data.graph.edges.len });
}

fn renderJson(allocator: std.mem.Allocator, ir_data: ir.IR, output_path: []const u8) !void {
    // Allocator will be used for json_emitter
    const file = if (std.mem.eql(u8, output_path, "-"))
        std.fs.File.stdout()
    else
        try std.fs.cwd().createFile(output_path, .{});
    defer if (!std.mem.eql(u8, output_path, "-")) file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);

    // Use json_emitter instead of direct JSON stringify
    var json_emitter_instance = json_emitter.JsonEmitter(@TypeOf(writer)).init(allocator, &writer);
    try json_emitter_instance.emit(ir_data);
    try writer.interface.flush();

    const output_desc = if (std.mem.eql(u8, output_path, "-")) "stdout" else output_path;
    try diag.printOk("JSON rendered to {s} ({d} nodes, {d} edges)", .{ output_desc, ir_data.graph.nodes.len, ir_data.graph.edges.len });
}
