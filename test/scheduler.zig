const std = @import("std");
const testing = std.testing;
const plugin_loader = @import("plugin_loader");
const cache = @import("cache");

test "worker context style loop handles sub-slice lengths" {
    const MockWorkItem = struct {
        processed: bool = false,
        processing_time_ms: u64 = 0,
    };

    const MockContext = struct {
        const Self = @This();
        work_items: []MockWorkItem,

        fn process(self: *Self, total_time_ms: u64) void {
            for (self.work_items) |*item| {
                item.processed = true;
            }

            const count = self.work_items.len;
            if (count == 0) return;

            const per_item = total_time_ms / @as(u64, @intCast(count));
            for (self.work_items) |*item| {
                item.processing_time_ms = per_item;
            }
        }
    };

    var items = [_]MockWorkItem{ .{}, .{}, .{} };

    var context = MockContext{ .work_items = items[1..] };
    context.process(90);

    try testing.expect(!items[0].processed);
    try testing.expect(items[1].processed);
    try testing.expect(items[2].processed);
    try testing.expectEqual(@as(u64, 45), items[1].processing_time_ms);
    try testing.expectEqual(@as(u64, 45), items[2].processing_time_ms);
}

pub fn runPluginHostCacheAlignmentTests(allocator: std.mem.Allocator) !void {
    try testCacheDirectoryAlignment(allocator);
    try testCacheStatsAlignment(allocator);
}

test "cache manager invalidates entries when plugin semver changes" {
    const allocator = testing.allocator;
    var ctx = try initHostTestDir(allocator);
    defer deinitHostTestDir(&ctx) catch {};

    const cache_dir_rel = ".repo2mmd/cache";
    try ctx.tmp_dir.makePath(cache_dir_rel);
    var manager = try cache.CacheManager.initAtPath(allocator, cache_dir_rel);
    defer manager.deinit();

    const file_path = "src/main.zig";
    const plugin_id = "zig";
    const plugin_abi = "1";
    const semver_a = "0.1.0";
    const semver_b = "0.2.0";
    const content = "const std = @import(\"std\");\n";

    try manager.put(file_path, plugin_id, plugin_abi, semver_a, content, &.{}, &.{}, &.{});

    manager.resetRunStats();
    const hit_entry = try manager.get(allocator, file_path, plugin_id, plugin_abi, semver_a, content);
    try testing.expect(hit_entry != null);
    if (hit_entry) |entry| {
        defer entry.deinit(allocator);
    }
    var stats = manager.getStats();
    try testing.expectEqual(@as(u32, 1), stats.hits);

    manager.resetRunStats();
    const miss_entry = try manager.get(allocator, file_path, plugin_id, plugin_abi, semver_b, content);
    try testing.expect(miss_entry == null);
    stats = manager.getStats();
    try testing.expectEqual(@as(u32, 1), stats.misses);
}

fn testCacheDirectoryAlignment(allocator: std.mem.Allocator) !void {
    var ctx = try initHostTestDir(allocator);
    defer deinitHostTestDir(&ctx) catch {};

    var host = plugin_loader.HostServices{ .allocator = allocator };
    const host_table = host.createHostTable();
    try testing.expect(host_table.cache_put != null);

    const key = "cache-alignment-test";
    const CachePutFnPointerType = @TypeOf(host_table.cache_put.?);
    const CachePutFnType = @typeInfo(CachePutFnPointerType).pointer.child;
    const CachePutFnInfo = @typeInfo(CachePutFnType);
    const PathParamType = CachePutFnInfo.@"fn".params[1].type.?;
    const PathValueType = @typeInfo(PathParamType).pointer.child;

    var path_view = PathValueType{ .data = key.ptr, .len = key.len };

    const payload = "plugin-cache-payload";
    const payload_ptr: *const anyopaque = @ptrCast(payload.ptr);

    const path_ptr: PathParamType = @ptrCast(&path_view);
    const wrote = host_table.cache_put.?(host_table.cache_state, path_ptr, payload_ptr, payload.len);
    try testing.expect(wrote);

    var repo_dir = try std.fs.cwd().openDir(".repo2mmd", .{ .iterate = true });
    defer repo_dir.close();

    var cache_dir = try repo_dir.openDir("cache", .{ .iterate = true });
    defer cache_dir.close();

    var iter = cache_dir.iterate();
    var found = false;
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".cache")) {
            found = true;
            break;
        }
    }

    try testing.expect(found);
}

fn testCacheStatsAlignment(allocator: std.mem.Allocator) !void {
    var ctx = try initHostTestDir(allocator);
    defer deinitHostTestDir(&ctx) catch {};

    var host = plugin_loader.HostServices{ .allocator = allocator };
    const host_table = host.createHostTable();
    try testing.expect(host_table.cache_put != null);

    const key = "stats-alignment-test";
    const CachePutFnPointerType = @TypeOf(host_table.cache_put.?);
    const CachePutFnType = @typeInfo(CachePutFnPointerType).pointer.child;
    const CachePutFnInfo = @typeInfo(CachePutFnType);
    const PathParamType = CachePutFnInfo.@"fn".params[1].type.?;
    const PathValueType = @typeInfo(PathParamType).pointer.child;

    var path_view = PathValueType{ .data = key.ptr, .len = key.len };

    const payload = "stats-payload";
    const payload_ptr: *const anyopaque = @ptrCast(payload.ptr);

    const path_ptr: PathParamType = @ptrCast(&path_view);
    const wrote = host_table.cache_put.?(host_table.cache_state, path_ptr, payload_ptr, payload.len);
    try testing.expect(wrote);

    const cache_dir_rel = ".repo2mmd/cache";
    try ctx.tmp_dir.makePath(cache_dir_rel);
    var manager = try cache.CacheManager.initAtPath(allocator, cache_dir_rel);
    defer manager.deinit();

    try manager.refreshEntryStats();
    const stats = manager.getStats();

    try testing.expect(stats.entries >= 1);
    try testing.expect(stats.total_size_bytes >= payload.len);
}

const HostTestContext = struct {
    tmp_dir: std.fs.Dir,
    original_dir: std.fs.Dir,
    original_path: []u8,
    tmp_path: []u8,
    allocator: std.mem.Allocator,
};

fn initHostTestDir(allocator: std.mem.Allocator) !HostTestContext {
    const cwd = std.fs.cwd();
    const original_path = try cwd.realpathAlloc(allocator, ".");
    const original_dir = try std.fs.openDirAbsolute(original_path, .{});
    const timestamp = std.time.nanoTimestamp();
    const tmp_path = try std.fmt.allocPrint(allocator, ".zig-cache/test-tmp-host-{d}", .{timestamp});
    errdefer allocator.free(tmp_path);
    cwd.deleteTree(tmp_path) catch {};
    var tmp_dir = try cwd.makeOpenPath(tmp_path, .{ .iterate = true, .access_sub_paths = true });
    try tmp_dir.setAsCwd();

    return HostTestContext{
        .tmp_dir = tmp_dir,
        .original_dir = original_dir,
        .original_path = original_path,
        .tmp_path = tmp_path,
        .allocator = allocator,
    };
}

fn deinitHostTestDir(ctx: *HostTestContext) !void {
    ctx.tmp_dir.close();
    try ctx.original_dir.setAsCwd();
    ctx.original_dir.close();
    std.fs.cwd().deleteTree(ctx.tmp_path) catch {};
    ctx.allocator.free(ctx.original_path);
    ctx.allocator.free(ctx.tmp_path);
}
