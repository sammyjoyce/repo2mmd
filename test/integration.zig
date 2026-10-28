const std = @import("std");

pub fn run(allocator: std.mem.Allocator) !void {
    std.debug.print("Running end-to-end integration tests...\n", .{});

    try testCompleteWorkflow(allocator);
    try testDifferentOutputFormats(allocator);
    try testLargeRepository(allocator);
    try testErrorHandling(allocator);

    std.debug.print("✓ All integration tests passed\n", .{});
}

fn testCompleteWorkflow(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing complete workflow...\n", .{});

    // Create a temporary directory with a realistic project structure
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    // Create project structure
    try tmp.dir.makePath("src");
    try tmp.dir.makePath("tests");
    try tmp.dir.makePath("docs");

    // Create source files with dependencies
    const main_content =
        \\const std = @import("std");
        \\const auth = @import("auth.zig");
        \\const database = @import("database.zig");
        \\const utils = @import("utils.zig");
        \\
        \\pub fn main() !void {
        \\    const user = auth.init("admin", "password");
        \\    _ = user.authenticate("password");
        \\    const db = try database.connect("localhost");
        \\    _ = db.query("SELECT * FROM users");
        \\    utils.log("Application started");
        \\}
    ;
    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = main_content });

    const auth_content =
        \\const std = @import("std");
        \\const crypto = @import("crypto.zig");
        \\
        \\pub const User = struct {
        \\    name: []const u8,
        \\    password_hash: []const u8,
        \\
        \\    pub fn init(name: []const u8, password: []const u8) User {
        \\        return User{
        \\            .name = name,
        \\            .password_hash = crypto.hashPassword(password),
        \\        };
        \\    }
        \\
        \\    pub fn authenticate(self: User, password: []const u8) bool {
        \\        return std.mem.eql(u8, self.password_hash, crypto.hashPassword(password));
        \\    }
        \\};
    ;
    try tmp.dir.writeFile(.{ .sub_path = "src/auth.zig", .data = auth_content });

    const database_content =
        \\const std = @import("std");
        \\const utils = @import("utils.zig");
        \\
        \\pub const Database = struct {
        \\    connection: []const u8,
        \\
        \\    pub fn connect(host: []const u8) !Database {
        \\        utils.log("Connecting to database");
        \\        return Database{ .connection = host };
        \\    }
        \\
        \\    pub fn query(self: Database, sql: []const u8) []const u8 {
        \\        _ = self;
        \\        utils.log("Executing query: {s}", .{sql});
        \\        return "results";
        \\    }
        \\};
    ;
    try tmp.dir.writeFile(.{ .sub_path = "src/database.zig", .data = database_content });

    const utils_content =
        \\const std = @import("std");
        \\
        \\pub fn log(comptime fmt: []const u8, args: anytype) void {
        \\    std.debug.print(fmt ++ "\n", args);
        \\}
    ;
    try tmp.dir.writeFile(.{ .sub_path = "src/utils.zig", .data = utils_content });

    const crypto_content =
        \\const std = @import("std");
        \\
        \\pub fn hashPassword(password: []const u8) []const u8 {
        \\    _ = password;
        \\    return "hashed_password";
        \\}
    ;
    try tmp.dir.writeFile(.{ .sub_path = "src/crypto.zig", .data = crypto_content });

    // Test JSON output
    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    const json_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/repo2mmd", "graph", "--root", root_path, "--format", "json" },
    });
    defer allocator.free(json_result.stdout);
    defer allocator.free(json_result.stderr);

    try std.testing.expectEqual(json_result.term.Exited, 0);

    // JSON is written to a file, read it from the expected location
    const json_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ root_path, std.fs.path.basename(root_path) });
    defer allocator.free(json_file_path);

    const json_file = try std.fs.cwd().openFile(json_file_path, .{});
    defer json_file.close();

    const json_content = try json_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    try std.testing.expect(json_content.len > 0);

    // Parse and validate JSON structure
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const manifest = root.get("manifest").?.object;
    const graph = root.get("graph").?.object;

    // Validate manifest
    try std.testing.expectEqualStrings("Deps", manifest.get("graph_type").?.string);
    try std.testing.expectEqualStrings(root_path, manifest.get("input_root").?.string);
    try std.testing.expect(manifest.get("node_count").?.integer > 0);
    try std.testing.expect(manifest.get("edge_count").?.integer > 0);

    // Validate graph structure
    const nodes = graph.get("nodes").?.array.items;
    const edges = graph.get("edges").?.array.items;

    try std.testing.expectEqual(@as(usize, @intCast(manifest.get("node_count").?.integer)), nodes.len);
    try std.testing.expectEqual(@as(usize, @intCast(manifest.get("edge_count").?.integer)), edges.len);

    // Test Mermaid (text) output
    const mermaid_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/repo2mmd", "graph", "--root", root_path, "--format", "text" },
    });
    defer allocator.free(mermaid_result.stdout);
    defer allocator.free(mermaid_result.stderr);

    try std.testing.expectEqual(mermaid_result.term.Exited, 0);

    // Mermaid is written to a file, read it from the expected location
    const mermaid_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.mmd", .{ root_path, std.fs.path.basename(root_path) });
    defer allocator.free(mermaid_file_path);

    const mermaid_file = try std.fs.cwd().openFile(mermaid_file_path, .{});
    defer mermaid_file.close();

    const mermaid_content = try mermaid_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(mermaid_content);

    try std.testing.expect(mermaid_content.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, mermaid_content, "```mermaid"));
    try std.testing.expect(std.mem.indexOf(u8, mermaid_content, "graph TD") != null);
    try std.testing.expect(std.mem.indexOf(u8, mermaid_content, "main.zig") != null);

    std.debug.print("    ✓ Complete workflow test passed\n", .{});
}

fn testDifferentOutputFormats(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing different output formats...\n", .{});

    // Create a simple test repository
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.writeFile(.{ .sub_path = "src/test.zig", .data = "const std = @import(\"std\");" });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    const basename = std.fs.path.basename(root_path);

    // Test JSON format
    const json_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/repo2mmd", "graph", "--root", root_path, "--format", "json" },
    });
    defer allocator.free(json_result.stdout);
    defer allocator.free(json_result.stderr);

    try std.testing.expectEqual(json_result.term.Exited, 0);

    const json_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ root_path, basename });
    defer allocator.free(json_file_path);

    const json_file = try std.fs.cwd().openFile(json_file_path, .{});
    defer json_file.close();

    const json_content = try json_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    try std.testing.expect(json_content.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, json_content, "{"));

    // Test Mermaid (text) format
    const mermaid_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/repo2mmd", "graph", "--root", root_path, "--format", "text" },
    });
    defer allocator.free(mermaid_result.stdout);
    defer allocator.free(mermaid_result.stderr);

    try std.testing.expectEqual(mermaid_result.term.Exited, 0);

    const mermaid_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.mmd", .{ root_path, basename });
    defer allocator.free(mermaid_file_path);

    const mermaid_file = try std.fs.cwd().openFile(mermaid_file_path, .{});
    defer mermaid_file.close();

    const mermaid_content = try mermaid_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(mermaid_content);

    try std.testing.expect(mermaid_content.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, mermaid_content, "```mermaid"));
    try std.testing.expect(std.mem.indexOf(u8, mermaid_content, "graph TD") != null);

    std.debug.print("    ✓ Supported output formats (JSON and text/Mermaid) work correctly\n", .{});
}

fn testLargeRepository(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing large repository handling...\n", .{});

    // Create a repository with many files
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.makePath("src/modules");
    try tmp.dir.makePath("src/utils");
    try tmp.dir.makePath("tests");

    // Create many source files
    for (0..50) |i| {
        const module_name = try std.fmt.allocPrint(allocator, "module_{}.zig", .{i});
        defer allocator.free(module_name);

        const content = try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\const utils = @import("../utils/utils.zig");
            \\
            \\pub fn func_{d}() void {{
            \\    utils.log("Function {d} called");
            \\}}
        , .{ i, i });
        defer allocator.free(content);

        const module_path = try std.fmt.allocPrint(allocator, "src/modules/{s}", .{module_name});
        defer allocator.free(module_path);
        try tmp.dir.writeFile(.{ .sub_path = module_path, .data = content });
    }

    // Create utils file
    const utils_content = "const std = @import(\"std\");\npub fn log(comptime fmt: []const u8, args: anytype) void { std.debug.print(fmt ++ \"\\n\", args); }\n";
    try tmp.dir.writeFile(.{ .sub_path = "src/utils/utils.zig", .data = utils_content });

    // Create main file that imports all modules
    var main_content = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer main_content.deinit(allocator);

    const writer = main_content.writer(allocator);
    try writer.print("const std = @import(\"std\");\n", .{});
    try writer.print("const utils = @import(\"utils/utils.zig\");\n", .{});

    for (0..50) |i| {
        try writer.print("const module_{d} = @import(\"modules/module_{d}.zig\");\n", .{ i, i });
    }

    try writer.print("\npub fn main() !void {{\n", .{});
    try writer.print("    utils.log(\"Application started\");\n", .{});

    for (0..50) |i| {
        try writer.print("    module_{d}.func_{d}();\n", .{ i, i });
    }

    try writer.print("}}\n", .{});

    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = main_content.items });

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    // Test that the tool can handle the large repository
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/repo2mmd", "graph", "--root", root_path, "--format", "json" },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(result.term.Exited, 0);

    // Read JSON from file
    const json_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ root_path, std.fs.path.basename(root_path) });
    defer allocator.free(json_file_path);

    const json_file = try std.fs.cwd().openFile(json_file_path, .{});
    defer json_file.close();

    const json_content = try json_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    try std.testing.expect(json_content.len > 0);

    // Parse and validate that we got the expected number of nodes
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const manifest = parsed.value.object.get("manifest").?.object;
    try std.testing.expect(manifest.get("node_count").?.integer >= 52); // 50 modules + main + utils

    std.debug.print("    ✓ Large repository handled correctly ({} nodes)\n", .{manifest.get("node_count").?.integer});
}

fn testErrorHandling(allocator: std.mem.Allocator) !void {
    std.debug.print("  Testing error handling...\n", .{});

    // Test non-existent directory
    const result1 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/repo2mmd", "graph", "--root", "/non/existent/path", "--format", "json" },
    });
    defer allocator.free(result1.stdout);
    defer allocator.free(result1.stderr);

    try std.testing.expect(result1.term.Exited != 0);
    try std.testing.expect(result1.stderr.len > 0);

    // Test invalid format
    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    const result2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig-out/bin/repo2mmd", "graph", "--root", root_path, "--format", "invalid" },
    });
    defer allocator.free(result2.stdout);
    defer allocator.free(result2.stderr);

    try std.testing.expect(result2.term.Exited != 0);
    try std.testing.expect(result2.stderr.len > 0);

    std.debug.print("    ✓ Error handling works correctly\n", .{});
}

test "Integration.endToEnd" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try run(allocator);
}
