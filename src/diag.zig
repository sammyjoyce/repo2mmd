const std = @import("std");

/// Severity levels supported by the minimal reporter.
pub const Severity = enum {
    Ok,
    Error,
};

/// Emit a formatted diagnostic at the chosen severity.
pub fn print(severity: Severity, comptime fmt: []const u8, args: anytype) !void {
    const file = switch (severity) {
        .Ok => std.fs.File.stderr(),
        .Error => std.fs.File.stderr(),
    };

    if (severity == .Error) {
        try file.writeAll("ERROR: ");
    }

    var buffer: [512]u8 = undefined;
    const message = try std.fmt.bufPrint(&buffer, fmt, args);
    try file.writeAll(message);
    try file.writeAll("\n");
}

pub fn printOk(comptime fmt: []const u8, args: anytype) !void {
    try print(.Ok, fmt, args);
}

pub fn printError(comptime fmt: []const u8, args: anytype) !void {
    try print(.Error, fmt, args);
}
