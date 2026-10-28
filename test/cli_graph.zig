const std = @import("std");
const testing = std.testing;

fn getBinaryPath(allocator: std.mem.Allocator) ![]const u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, "zig-out", "bin", "repo2mmd" });
}

test "graph command runs discovery and scheduler" {
    var tmp = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "const std = @import(\"std\");\n" });

    const root_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root_path);

    try ensureBinary();

    const binary_path = try getBinaryPath(testing.allocator);
    defer testing.allocator.free(binary_path);
    const result = try std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ binary_path, "graph", "--root", root_path },
        .cwd = null,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expectEqual(@as(u8, 0), result.term.Exited);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Analyzed 1 files under") != null);
}

test "graph command reports invalid root" {
    try ensureBinary();

    const binary_path = try getBinaryPath(testing.allocator);
    defer testing.allocator.free(binary_path);
    const result = try std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ binary_path, "graph", "--root", "./does-not-exist" },
        .cwd = null,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(result.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "ERROR:") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid root path") != null);
}

fn ensureBinary() !void {
    const binary_path = "zig-out/bin/repo2mmd";
    if (std.fs.cwd().access(binary_path, .{})) |_| {
        return;
    } else |_| {}

    const build_result = try std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "zig", "build" },
        .cwd = null,
    });
    defer testing.allocator.free(build_result.stdout);
    defer testing.allocator.free(build_result.stderr);

    if (build_result.term != .Exited or build_result.term.Exited != 0) {
        return CliGraphError.BuildFailed;
    }
}

const CliGraphError = error{BuildFailed};
