const std = @import("std");

// Command definitions - extracted from cli.zig to avoid circular dependencies
const commands = [_]Command{
    .{
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
    },
    .{
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
    },
    .{
        .name = "render",
        .summary = "Render a graph JSON to Mermaid",
        .help =
        \\Render a graph JSON file to a Mermaid diagram.
        \\
        \\This command takes the JSON output from the 'analyze' command
        \\and renders it as a Mermaid diagram.
        ,
    },
    .{
        .name = "explain",
        .summary = "Explain analysis results",
        .help =
        \\Provide detailed explanations for analysis results.
        \\
        \\This command helps understand why certain relationships
        \\were detected and how to interpret the diagram.
        ,
    },
    .{
        .name = "cache",
        .summary = "Manage analysis cache",
        .help =
        \\Manage the analysis cache to improve performance.
        \\
        \\Cache operations:
        \\  - Clear: Remove all cached data
        \\  - Info: Show cache statistics
        ,
    },
    .{
        .name = "config",
        .summary = "Manage configuration",
        .help =
        \\Manage repo2mmd configuration.
        \\
        \\Configuration operations:
        \\  - Show: Display current configuration
        \\  - Set: Update configuration values
        \\  - Reset: Reset to defaults
        ,
    },
};

const Command = struct {
    name: []const u8,
    summary: []const u8,
    help: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <output_file>\n", .{args[0]});
        std.process.exit(1);
    }

    const output_path = args[1];

    if (std.fs.path.dirname(output_path)) |dir| {
        if (dir.len > 0) {
            try std.fs.cwd().makePath(dir);
        }
    }

    // Generate OpenCLI specification at runtime based on actual commands
    const opencli_spec = try generateOpenCliSpec(allocator);
    defer allocator.free(opencli_spec);

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(opencli_spec);

    std.debug.print("OpenCLI specification generated: {s}\n", .{output_path});
}

fn generateOpenCliSpec(allocator: std.mem.Allocator) ![]u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try buffer.appendSlice(allocator,
        \\{
        \\  "opencli": "0.1",
        \\  "info": {
        \\    "title": "repo2mmd",
        \\    "summary": "Repository to Mermaid diagram generator",
        \\    "description": "Scan repositories and emit Mermaid diagrams that reflect code structure with certainty tags.",
        \\    "version": "0.1.0",
        \\    "contact": {
        \\      "name": "Sam Joyce",
        \\      "url": "https://github.com/sammyjoyce/repo2mmd",
        \\      "email": "sam@example.com"
        \\    },
        \\    "license": {
        \\      "name": "MIT License",
        \\      "identifier": "MIT"
        \\    }
        \\  },
        \\  "conventions": {
        \\    "groupOptions": false,
        \\    "optionArgumentSeparator": " "
        \\  },
        \\  "arguments": [
        \\    {
        \\      "name": "command",
        \\      "required": true,
        \\      "arity": {
        \\        "minimum": 1,
        \\        "maximum": 1
        \\      },
        \\      "description": "The command to execute",
        \\      "allowedValues": ["generate", "analyze", "render", "explain", "cache", "config"]
        \\    }
        \\  ],
        \\  "options": [
        \\    {
        \\      "name": "help",
        \\      "required": false,
        \\      "aliases": ["h"],
        \\      "arguments": [],
        \\      "description": "Show help message and exit"
        \\    },
        \\    {
        \\      "name": "version",
        \\      "required": false,
        \\      "aliases": ["V"],
        \\      "arguments": [],
        \\      "description": "Show version information and exit"
        \\    },
        \\    {
        \\      "name": "quiet",
        \\      "required": false,
        \\      "aliases": ["q"],
        \\      "arguments": [],
        \\      "description": "Suppress non-error output"
        \\    },
        \\    {
        \\      "name": "verbose",
        \\      "required": false,
        \\      "aliases": ["v"],
        \\      "arguments": [],
        \\      "description": "Increase verbosity (can be used multiple times)"
        \\    },
        \\    {
        \\      "name": "log-level",
        \\      "required": false,
        \\      "arguments": [{"name": "level", "description": "Log level (trace, debug, info, warn, error)"}],
        \\      "description": "Set logging level"
        \\    },
        \\    {
        \\      "name": "color",
        \\      "required": false,
        \\      "arguments": [{"name": "mode", "description": "Color mode (auto, always, never)"}],
        \\      "description": "Control color output"
        \\    },
        \\    {
        \\      "name": "config",
        \\      "required": false,
        \\      "arguments": [{"name": "file", "description": "Configuration file path"}],
        \\      "description": "Path to configuration file"
        \\    },
        \\    {
        \\      "name": "cache",
        \\      "required": false,
        \\      "arguments": [{"name": "mode", "description": "Cache mode (rw, ro, off)"}],
        \\      "description": "Cache operation mode"
        \\    },
        \\    {
        \\      "name": "plugin-dir",
        \\      "required": false,
        \\      "arguments": [{"name": "dir", "description": "Plugin directory path"}],
        \\      "description": "Add plugin directory (can be used multiple times)"
        \\    }
        \\  ],
        \\  "commands": [
        \\
    );

    // Generate command specifications based on actual commands
    for (commands, 0..) |cmd, i| {
        if (i > 0) try buffer.appendSlice(allocator, ",\n");

        try buffer.appendSlice(allocator,
            \\    {
            \\      "name": "
        );
        try buffer.appendSlice(allocator, cmd.name);
        try buffer.appendSlice(allocator,
            \\",
            \\      "summary": "
        );
        try buffer.appendSlice(allocator, cmd.summary);
        try buffer.appendSlice(allocator,
            \\",
            \\      "description": "
        );

        // Escape quotes in help text
        const escaped_help = try escapeJsonString(allocator, cmd.help);
        defer allocator.free(escaped_help);
        try buffer.appendSlice(allocator, escaped_help);

        try buffer.appendSlice(allocator,
            \\",
            \\      "arguments": [
            \\        {
            \\          "name": "paths",
            \\          "required": false,
            \\          "arity": {
            \\            "minimum": 0,
            \\            "maximum": "unbounded"
            \\          },
            \\          "description": "Paths to analyze"
            \\        }
            \\      ],
            \\      "options": [
        );

        // Add command-specific options based on the command
        if (std.mem.eql(u8, cmd.name, "generate") or std.mem.eql(u8, cmd.name, "analyze")) {
            try buffer.appendSlice(allocator,
                \\        {
                \\          "name": "output",
                \\          "required": false,
                \\          "arguments": [{"name": "file", "description": "Output file path"}],
                \\          "description": "Output file (default: stdout)"
                \\        },
                \\        {
                \\          "name": "format",
                \\          "required": false,
                \\          "arguments": [{"name": "fmt", "description": "Output format"}],
                \\          "description": "Output format (mermaid or json)"
                \\        },
                \\        {
                \\          "name": "jobs",
                \\          "required": false,
                \\          "arguments": [{"name": "n", "description": "Number of jobs"}],
                \\          "description": "Number of parallel jobs"
                \\        },
                \\        {
                \\          "name": "include",
                \\          "required": false,
                \\          "arguments": [{"name": "pattern", "description": "Include pattern"}],
                \\          "description": "Include files matching pattern (can be used multiple times)"
                \\        },
                \\        {
                \\          "name": "exclude",
                \\          "required": false,
                \\          "arguments": [{"name": "pattern", "description": "Exclude pattern"}],
                \\          "description": "Exclude files matching pattern (can be used multiple times)"
                \\        },
                \\        {
                \\          "name": "language",
                \\          "required": false,
                \\          "arguments": [{"name": "lang", "description": "Language filter"}],
                \\          "description": "Include only specific languages (can be used multiple times)"
                \\        },
                \\        {
                \\          "name": "root",
                \\          "required": false,
                \\          "arguments": [{"name": "path", "description": "Root path"}],
                \\          "description": "Root directory to analyze"
                \\        }
            );
        } else if (std.mem.eql(u8, cmd.name, "render")) {
            try buffer.appendSlice(allocator,
                \\        {
                \\          "name": "output",
                \\          "required": false,
                \\          "arguments": [{"name": "file", "description": "Output file path"}],
                \\          "description": "Output file (default: stdout)"
                \\        },
                \\        {
                \\          "name": "format",
                \\          "required": false,
                \\          "arguments": [{"name": "fmt", "description": "Output format"}],
                \\          "description": "Output format (mermaid or json)"
                \\        }
            );
        } else if (std.mem.eql(u8, cmd.name, "cache")) {
            try buffer.appendSlice(allocator,
                \\        {
                \\          "name": "clear",
                \\          "required": false,
                \\          "arguments": [],
                \\          "description": "Clear the cache"
                \\        },
                \\        {
                \\          "name": "info",
                \\          "required": false,
                \\          "arguments": [],
                \\          "description": "Show cache information"
                \\        }
            );
        }

        try buffer.appendSlice(allocator,
            \\      ]
            \\    }
        );
    }

    try buffer.appendSlice(allocator,
        \\  ]
        \\}
        \\
    );

    return buffer.toOwnedSlice(allocator);
}

fn escapeJsonString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).initCapacity(allocator, input.len) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer result.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '"' => try result.appendSlice(allocator, "\\\""),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }

    return result.toOwnedSlice(allocator);
}
