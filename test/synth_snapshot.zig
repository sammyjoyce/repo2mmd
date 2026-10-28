const std = @import("std");
const testing = std.testing;

pub fn runSynthSnapshots(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing synth repo CLI snapshots...\n", .{});

    try ensureBinary(allocator);

    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_root);

    const repo_path = try std.fs.cwd().realpathAlloc(allocator, "test_synth_repo");
    defer allocator.free(repo_path);

    const mermaid_output = try std.fs.path.join(allocator, &.{ tmp_root, "snapshot.mmd" });
    defer allocator.free(mermaid_output);

    const json_output = try std.fs.path.join(allocator, &.{ tmp_root, "snapshot.json" });
    defer allocator.free(json_output);

    const plugin_dir = try locatePluginDir(allocator, binary_path);
    defer allocator.free(plugin_dir);

    const mermaid_output_arg = try std.fmt.allocPrint(allocator, "--output={s}", .{mermaid_output});
    defer allocator.free(mermaid_output_arg);
    try runCommand(allocator, binary_path, &.{
        "generate",
        "--format=mermaid",
        "--plugin-dir",
        plugin_dir,
        mermaid_output_arg,
    }, repo_path);

    const json_output_arg = try std.fmt.allocPrint(allocator, "--output={s}", .{json_output});
    defer allocator.free(json_output_arg);
    try runCommand(allocator, binary_path, &.{
        "generate",
        "--format=json",
        "--plugin-dir",
        plugin_dir,
        json_output_arg,
    }, repo_path);

    const actual_mermaid = try readFileAbsolute(allocator, mermaid_output);
    defer allocator.free(actual_mermaid);
    const golden_mermaid = try std.fs.cwd().readFileAlloc(allocator, "test/golden/synth_repo_golden.mmd", 8 * 1024 * 1024);
    defer allocator.free(golden_mermaid);

    const normalized_actual_mermaid = try normalizeMermaidFunctionIds(allocator, actual_mermaid);
    defer allocator.free(normalized_actual_mermaid);
    const normalized_golden_mermaid = try normalizeMermaidFunctionIds(allocator, golden_mermaid);
    defer allocator.free(normalized_golden_mermaid);

    try testing.expectEqualStrings(normalized_golden_mermaid, normalized_actual_mermaid);

    const actual_json = try readFileAbsolute(allocator, json_output);
    defer allocator.free(actual_json);
    const golden_json = try std.fs.cwd().readFileAlloc(allocator, "test/golden/synth_repo_golden.json", 8 * 1024 * 1024);
    defer allocator.free(golden_json);

    const repo_basename = std.fs.path.basename(repo_path);
    const placeholder = try std.fmt.allocPrint(allocator, "<REPO_ROOT>/{s}", .{repo_basename});
    defer allocator.free(placeholder);

    const normalized_actual_json = try replaceAll(allocator, actual_json, repo_path, placeholder);
    defer allocator.free(normalized_actual_json);

    var actual_doc = try std.json.parseFromSlice(std.json.Value, allocator, normalized_actual_json, .{});
    defer actual_doc.deinit();
    var golden_doc = try std.json.parseFromSlice(std.json.Value, allocator, golden_json, .{});
    defer golden_doc.deinit();

    try testing.expect(jsonValuesDeepEqual(golden_doc.value, actual_doc.value));

    std.debug.print("✓ Synth repo snapshots match golden outputs\n", .{});
}

fn runCommand(allocator: std.mem.Allocator, binary_path: []const u8, args: []const []const u8, cwd: ?[]const u8) !void {
    var argv = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer argv.deinit(allocator);

    try argv.append(allocator, binary_path);
    for (args) |arg| try argv.append(allocator, arg);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
        .cwd = cwd orelse ".",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        for (argv.items, 0..) |arg, i| {
            std.debug.print("argv[{}]: {s}\n", .{ i, arg });
        }
        std.debug.print("stdout: {s}\nstderr: {s}\n", .{ result.stdout, result.stderr });
    }
    try testing.expect(result.term == .Exited and result.term.Exited == 0);
}

fn readFileAbsolute(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 8 * 1024 * 1024);
}

fn getBinaryPath(allocator: std.mem.Allocator) ![]u8 {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return std.fs.path.join(allocator, &.{ cwd, "zig-out", "bin", "repo2mmd" });
}

fn locatePluginDir(allocator: std.mem.Allocator, binary_path: []const u8) ![]u8 {
    const bin_dir_path = std.fs.path.dirname(binary_path) orelse return error.PluginDirNotFound;
    const bin_dir = try std.fs.cwd().realpathAlloc(allocator, bin_dir_path);
    defer allocator.free(bin_dir);

    const project_root_rel = try std.fs.path.join(allocator, &.{ bin_dir, "..", ".." });
    defer allocator.free(project_root_rel);

    const project_root = try std.fs.cwd().realpathAlloc(allocator, project_root_rel);
    defer allocator.free(project_root);

    const plugin_dir_rel = try std.fs.path.join(allocator, &.{ project_root, "zig-out", "lib", "repo2mmd", "plugins" });
    defer allocator.free(plugin_dir_rel);

    return std.fs.cwd().realpathAlloc(allocator, plugin_dir_rel);
}

fn ensureBinary(allocator: std.mem.Allocator) !void {
    const binary_path = try getBinaryPath(allocator);
    defer allocator.free(binary_path);

    const file = std.fs.cwd().openFile(binary_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Building repo2mmd binary for snapshot tests...\n", .{});
            const result = try std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "zig", "build" } });
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            if (result.term != .Exited or result.term.Exited != 0) {
                std.debug.print("Build failed:\n{s}\n", .{result.stderr});
                return error.BuildFailed;
            }
            return;
        },
        else => return err,
    };
    file.close();
}

fn replaceAll(allocator: std.mem.Allocator, text: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) {
        return try allocator.dupe(u8, text);
    }
    return try std.mem.replaceOwned(u8, allocator, text, needle, replacement);
}

fn normalizeMermaidFunctionIds(allocator: std.mem.Allocator, mermaid: []const u8) ![]u8 {
    const prefix = "func_";
    var output = try std.ArrayList(u8).initCapacity(allocator, mermaid.len);
    errdefer output.deinit(allocator);
    var writer = output.writer(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, mermaid, cursor, prefix)) |match_index| {
        try writer.writeAll(mermaid[cursor..match_index]);

        var id_end = match_index + prefix.len;
        while (id_end < mermaid.len and isIdChar(mermaid[id_end])) : (id_end += 1) {}

        const id_body = mermaid[(match_index + prefix.len)..id_end];

        var tokens = try std.ArrayList([]const u8).initCapacity(allocator, 4);
        defer tokens.deinit(allocator);
        var tokenizer = std.mem.tokenizeScalar(u8, id_body, '_');
        while (tokenizer.next()) |token| {
            try tokens.append(allocator, token);
        }

        if (tokens.items.len == 0) {
            try writer.writeAll(mermaid[match_index..id_end]);
        } else {
            var kept = try std.ArrayList([]const u8).initCapacity(allocator, tokens.items.len);
            defer kept.deinit(allocator);

            for (tokens.items, 0..) |token, idx| {
                const is_last = idx == tokens.items.len - 1;
                const keep = is_last or !startsWithUpper(token);
                if (keep) {
                    try kept.append(allocator, token);
                }
            }

            if (kept.items.len == tokens.items.len or kept.items.len == 0) {
                try writer.writeAll(mermaid[match_index..id_end]);
            } else {
                try writer.writeAll(prefix);
                var first = true;
                for (kept.items) |token| {
                    if (!first) try writer.writeByte('_');
                    try writer.writeAll(token);
                    first = false;
                }
            }
        }

        cursor = id_end;
    }

    try writer.writeAll(mermaid[cursor..]);
    return output.toOwnedSlice(allocator);
}

fn isIdChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '/';
}

fn startsWithUpper(token: []const u8) bool {
    return token.len > 0 and std.ascii.isUpper(token[0]);
}

fn jsonValuesDeepEqual(a: std.json.Value, b: std.json.Value) bool {
    if (a == .object and b == .object) {
        return jsonObjectsDeepEqual(a.object, b.object);
    } else if (a == .array and b == .array) {
        if (a.array.items.len != b.array.items.len) return false;
        for (a.array.items, b.array.items) |a_item, b_item| {
            if (!jsonValuesDeepEqual(a_item, b_item)) return false;
        }
        return true;
    } else if (a == .string and b == .string) {
        return std.mem.eql(u8, a.string, b.string);
    } else if (a == .integer and b == .integer) {
        return a.integer == b.integer;
    } else if (a == .float and b == .float) {
        return a.float == b.float;
    } else if (a == .bool and b == .bool) {
        return a.bool == b.bool;
    } else if (a == .null and b == .null) {
        return true;
    }

    return false;
}

fn jsonObjectsDeepEqual(expected: std.json.ObjectMap, actual: std.json.ObjectMap) bool {
    var expected_it = expected.iterator();
    while (expected_it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.eql(u8, key, "range")) continue;
        const expected_value = entry.value_ptr.*;
        const actual_value = actual.get(key) orelse {
            if (std.mem.eql(u8, key, "range")) continue;
            return false;
        };
        if (!jsonValuesDeepEqualKeyed(key, expected_value, actual_value)) return false;
    }

    var actual_it = actual.iterator();
    while (actual_it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.eql(u8, key, "range")) continue;
        if (expected.get(key) == null) return false;
    }

    return true;
}

fn jsonValuesDeepEqualKeyed(key: []const u8, expected: std.json.Value, actual: std.json.Value) bool {
    if (expected == .string and actual == .string) {
        if (std.mem.eql(u8, key, "id") and std.mem.startsWith(u8, expected.string, "func_") and std.mem.startsWith(u8, actual.string, "func_")) {
            return funcIdsEqualNormalized(expected.string, actual.string);
        }
        if (std.mem.eql(u8, key, "fqname")) {
            return fqnameEqualNormalized(expected.string, actual.string);
        }
    }

    return jsonValuesDeepEqual(expected, actual);
}

fn fqnameEqualNormalized(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, trimNamespace(a), trimNamespace(b));
}

fn trimNamespace(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        return name[idx + 1 ..];
    }
    return name;
}

const FuncTokenBuffer = struct {
    items: [32][]const u8 = undefined,
    len: usize = 0,

    fn append(self: *FuncTokenBuffer, item: []const u8) bool {
        if (self.len >= self.items.len) return false;
        self.items[self.len] = item;
        self.len += 1;
        return true;
    }

    fn slice(self: *const FuncTokenBuffer) []const []const u8 {
        return self.items[0..self.len];
    }
};

fn funcIdsEqualNormalized(a: []const u8, b: []const u8) bool {
    var tokens_a = FuncTokenBuffer{};
    var tokens_b = FuncTokenBuffer{};

    if (!canonicalizeFuncIdTokens(a, &tokens_a)) return false;
    if (!canonicalizeFuncIdTokens(b, &tokens_b)) return false;

    if (tokens_a.len != tokens_b.len) return false;
    for (tokens_a.slice(), tokens_b.slice()) |token_a, token_b| {
        if (!std.mem.eql(u8, token_a, token_b)) return false;
    }
    return true;
}

fn canonicalizeFuncIdTokens(id: []const u8, out: *FuncTokenBuffer) bool {
    if (!std.mem.startsWith(u8, id, "func_")) {
        return out.append(id);
    }

    var raw = FuncTokenBuffer{};
    var rest = id["func_".len..];
    while (rest.len > 0) {
        const idx = std.mem.indexOfScalar(u8, rest, '_') orelse {
            if (!raw.append(rest)) return false;
            break;
        };
        if (!raw.append(rest[0..idx])) return false;
        rest = rest[idx + 1 ..];
    }

    if (raw.len == 0) return true;
    const last_index = raw.len - 1;
    for (raw.slice(), 0..) |token, index| {
        if (index != last_index and startsWithUpper(token)) continue;
        if (!out.append(token)) return false;
    }

    if (out.len == 0) {
        return out.append(raw.slice()[last_index]);
    }

    return true;
}
