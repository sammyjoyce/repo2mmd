const std = @import("std");
const ir = @import("ir");
const path_resolver = @import("path_resolver");

const SUMMARY_FILENAME = "cache_summary.json";

// Schema version for cache compatibility
const R2M_SCHEMA_VERSION: u32 = 2;

/// Cache entry header containing metadata for cache validation
pub const CacheHeader = struct {
    schema_version: u32,
    plugin_id: []const u8,
    plugin_abi_version: []const u8,
    plugin_semver: []const u8,
    file_hash: u64,
    created_at: i64,
    entry_size: u64,

    pub fn serialize(self: CacheHeader, writer: anytype) !void {
        try writer.writeInt(u32, self.schema_version, .little);
        try writer.writeInt(u32, @intCast(self.plugin_id.len), .little);
        try writer.writeAll(self.plugin_id);
        try writer.writeInt(u32, @intCast(self.plugin_abi_version.len), .little);
        try writer.writeAll(self.plugin_abi_version);
        try writer.writeInt(u32, @intCast(self.plugin_semver.len), .little);
        try writer.writeAll(self.plugin_semver);
        try writer.writeInt(u64, self.file_hash, .little);
        try writer.writeInt(i64, self.created_at, .little);
        try writer.writeInt(u64, self.entry_size, .little);
    }

    pub fn deserialize(allocator: std.mem.Allocator, reader: anytype) !CacheHeader {
        const schema_version = try reader.readInt(u32, .little);

        if (schema_version != R2M_SCHEMA_VERSION) {
            return error.SchemaMismatch;
        }

        const plugin_id_len = try reader.readInt(u32, .little);
        const plugin_id = try allocator.alloc(u8, plugin_id_len);
        try reader.readNoEof(plugin_id);

        const plugin_abi_version_len = try reader.readInt(u32, .little);
        const plugin_abi_version = try allocator.alloc(u8, plugin_abi_version_len);
        try reader.readNoEof(plugin_abi_version);

        const plugin_semver_len = try reader.readInt(u32, .little);
        const plugin_semver = try allocator.alloc(u8, plugin_semver_len);
        try reader.readNoEof(plugin_semver);

        const file_hash = try reader.readInt(u64, .little);
        const created_at = try reader.readInt(i64, .little);
        const entry_size = try reader.readInt(u64, .little);

        return CacheHeader{
            .schema_version = schema_version,
            .plugin_id = plugin_id,
            .plugin_abi_version = plugin_abi_version,
            .plugin_semver = plugin_semver,
            .file_hash = file_hash,
            .created_at = created_at,
            .entry_size = entry_size,
        };
    }

    pub fn deinit(self: CacheHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.plugin_id);
        allocator.free(self.plugin_abi_version);
        allocator.free(self.plugin_semver);
    }
};

/// Cache entry containing parsed data for a single file
pub const CacheEntry = struct {
    nodes: []ir.Node,
    edges: []ir.Edge,
    diagnostics: []ir.Diagnostic,

    pub fn deinit(self: CacheEntry, allocator: std.mem.Allocator) void {
        for (self.nodes) |node| {
            allocator.free(node.id);
            allocator.free(node.lang);
            allocator.free(node.name);
            allocator.free(node.fqname);
            allocator.free(node.file);
            if (node.signature) |sig| allocator.free(sig);
            allocator.free(node.origin_plugin);
            if (node.module_id) |module_id| allocator.free(module_id);
            // Free individual tag strings before freeing the tags array
            for (node.tags) |tag| {
                allocator.free(tag);
            }
            allocator.free(node.tags);
        }
        allocator.free(self.nodes);

        for (self.edges) |edge| {
            allocator.free(edge.src);
            allocator.free(edge.dst);
            if (edge.certainty_reason) |reason| allocator.free(reason);
            // Free individual evidence path strings before freeing the array
            for (edge.evidence_paths) |path| {
                allocator.free(path);
            }
            allocator.free(edge.evidence_paths);
            allocator.free(edge.evidence_lines);
            // Free individual diagnostic ref IDs before freeing the array
            for (edge.diagnostics) |diag_ref| {
                allocator.free(diag_ref.id);
            }
            allocator.free(edge.diagnostics);
        }
        allocator.free(self.edges);

        for (self.diagnostics) |diag| {
            allocator.free(diag.id);
            allocator.free(diag.message);
            allocator.free(diag.file);
            // Free individual tag strings before freeing the tags array
            for (diag.tags) |tag| {
                allocator.free(tag);
            }
            allocator.free(diag.tags);
        }
        allocator.free(self.diagnostics);
    }
};

test "legacy cache headers trigger schema mismatch" {
    var header_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &header_bytes, 1, .little);

    var stream = std.io.fixedBufferStream(&header_bytes);
    try std.testing.expectError(error.SchemaMismatch, CacheHeader.deserialize(std.testing.allocator, stream.reader()));
}

/// Cache statistics for reporting
pub const CacheStats = struct {
    hits: u32,
    misses: u32,
    entries: u32,
    total_size_bytes: u64,

    pub fn hitRate(self: CacheStats) f32 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total)) * 100.0;
    }
};

const EntryStats = struct {
    count: u32,
    bytes: u64,
};

/// Cache manager for content-addressed file parsing results
pub const CacheManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cache_dir: std.fs.Dir,
    stats: CacheStats,
    summary_dirty: bool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const cache_path = path_resolver.getCacheDir(std.heap.page_allocator, .{}) catch |err| switch (err) {
            error.MissingHome => blk: {
                const cwd = try std.fs.cwd().realpathAlloc(std.heap.page_allocator, ".");
                defer std.heap.page_allocator.free(cwd);
                break :blk try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ cwd, ".repo2mmd", "cache" });
            },
            else => return err,
        };
        defer std.heap.page_allocator.free(cache_path);

        std.fs.makeDirAbsolute(cache_path) catch |mk_err| switch (mk_err) {
            error.PathAlreadyExists => {},
            error.FileNotFound => {
                if (std.fs.path.dirname(cache_path)) |parent| {
                    std.fs.makeDirAbsolute(parent) catch |parent_err| switch (parent_err) {
                        error.PathAlreadyExists => {},
                        else => return parent_err,
                    };
                    std.fs.makeDirAbsolute(cache_path) catch |retry_err| switch (retry_err) {
                        error.PathAlreadyExists => {},
                        else => return retry_err,
                    };
                }
            },
            else => return mk_err,
        };

        return initAtPath(allocator, cache_path);
    }

    pub fn initAtPath(allocator: std.mem.Allocator, cache_path: []const u8) !Self {
        try std.fs.cwd().makePath(cache_path);
        const cache_dir = try std.fs.cwd().openDir(cache_path, .{ .iterate = true });

        var manager = Self{
            .allocator = allocator,
            .cache_dir = cache_dir,
            .stats = .{
                .hits = 0,
                .misses = 0,
                .entries = 0,
                .total_size_bytes = 0,
            },
            .summary_dirty = false,
        };

        manager.loadSummary() catch {};

        const entry_stats = manager.recalculateEntryStats() catch EntryStats{
            .count = 0,
            .bytes = 0,
        };
        manager.stats.entries = entry_stats.count;
        manager.stats.total_size_bytes = entry_stats.bytes;

        return manager;
    }

    pub fn deinit(self: *Self) void {
        if (self.summary_dirty) {
            self.persistSummary() catch {};
        }
        self.cache_dir.close();
    }

    /// Generate cache key from file path and plugin information
    fn generateCacheKey(file_path: []const u8, plugin_id: []const u8, plugin_abi_version: []const u8, plugin_semver: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        const combined = try std.fmt.allocPrint(allocator, "{s}|{s}|{s}|{s}", .{ file_path, plugin_id, plugin_abi_version, plugin_semver });
        defer allocator.free(combined);

        const hash = std.hash.Wyhash.hash(0, combined);
        return std.fmt.allocPrint(allocator, "{x:0>16}.cache", .{hash});
    }

    /// Calculate file hash for content validation
    fn calculateFileHash(file_content: []const u8) u64 {
        return std.hash.Wyhash.hash(0, file_content);
    }

    /// Store parsing results in cache
    pub fn put(self: *Self, file_path: []const u8, plugin_id: []const u8, plugin_abi_version: []const u8, plugin_semver: []const u8, file_content: []const u8, nodes: []const ir.Node, edges: []const ir.Edge, diagnostics: []const ir.Diagnostic) !void {
        const cache_key = try generateCacheKey(file_path, plugin_id, plugin_abi_version, plugin_semver, self.allocator);
        defer self.allocator.free(cache_key);

        const file_hash = calculateFileHash(file_content);
        const created_at = std.time.timestamp();

        // Serialize cache entry
        var buffer = try self.allocator.alloc(u8, 1024 * 1024); // 1MB initial buffer
        defer self.allocator.free(buffer);
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        // Write placeholder for header (will update with actual size later)
        const header_pos = fbs.pos;
        try writer.writeInt(u64, 0, .little); // placeholder for header size

        // Serialize nodes
        try writer.writeInt(u32, @intCast(nodes.len), .little);
        for (nodes) |node| {
            try serializeNode(writer, node);
        }

        // Serialize edges
        try writer.writeInt(u32, @intCast(edges.len), .little);
        for (edges) |edge| {
            try serializeEdge(writer, edge);
        }

        // Serialize diagnostics
        try writer.writeInt(u32, @intCast(diagnostics.len), .little);
        for (diagnostics) |diag| {
            try serializeDiagnostic(writer, diag);
        }

        // Create header with actual entry size
        const entry_data = buffer[header_pos + 8 .. fbs.pos]; // skip placeholder
        const header = CacheHeader{
            .schema_version = R2M_SCHEMA_VERSION,
            .plugin_id = try self.allocator.dupe(u8, plugin_id),
            .plugin_abi_version = try self.allocator.dupe(u8, plugin_abi_version),
            .plugin_semver = try self.allocator.dupe(u8, plugin_semver),
            .file_hash = file_hash,
            .created_at = created_at,
            .entry_size = entry_data.len,
        };
        defer header.deinit(self.allocator);

        // Update header size and write actual header
        var header_buffer = try self.allocator.alloc(u8, 1024);
        defer self.allocator.free(header_buffer);
        var header_fbs = std.io.fixedBufferStream(header_buffer);
        const header_writer = header_fbs.writer();
        try header.serialize(header_writer);

        // Replace placeholder with actual header size
        var header_size_array: [8]u8 = undefined;
        std.mem.writeInt(u64, &header_size_array, @intCast(header_fbs.pos), .little);
        std.mem.copyForwards(u8, buffer[header_pos .. header_pos + 8], &header_size_array);

        // Write cache file
        const cache_file = try self.cache_dir.createFile(cache_key, .{});
        defer cache_file.close();

        // Write header size first
        var header_size_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &header_size_bytes, @intCast(header_fbs.pos), .little);
        try cache_file.writeAll(&header_size_bytes);

        // Write header data
        try cache_file.writeAll(header_buffer[0..header_fbs.pos]);
        try cache_file.writeAll(entry_data);

        self.stats.entries += 1;
        self.stats.total_size_bytes += @as(u64, @intCast(fbs.pos));
        self.summary_dirty = true;
    }

    /// Retrieve parsing results from cache
    pub fn get(self: *Self, allocator: std.mem.Allocator, file_path: []const u8, plugin_id: []const u8, plugin_abi_version: []const u8, plugin_semver: []const u8, file_content: []const u8) !?CacheEntry {
        const cache_key = try generateCacheKey(file_path, plugin_id, plugin_abi_version, plugin_semver, self.allocator);
        defer self.allocator.free(cache_key);

        const cache_file = self.cache_dir.openFile(cache_key, .{}) catch {
            self.stats.misses += 1;
            self.summary_dirty = true;
            return null;
        };
        defer cache_file.close();

        const file_content_hash = calculateFileHash(file_content);

        // Read and validate header
        var header_size_bytes: [8]u8 = undefined;
        _ = try cache_file.readAll(&header_size_bytes);
        const header_size = std.mem.readInt(u64, &header_size_bytes, .little);

        // Read header data
        const header_data = try self.allocator.alloc(u8, header_size);
        defer self.allocator.free(header_data);
        _ = try cache_file.readAll(header_data);

        var header_fbs = std.io.fixedBufferStream(header_data);
        var header = CacheHeader.deserialize(self.allocator, header_fbs.reader()) catch {
            self.stats.misses += 1;
            self.summary_dirty = true;
            return null;
        };
        defer header.deinit(self.allocator);

        // Validate cache entry
        if (header.schema_version != R2M_SCHEMA_VERSION) {
            self.stats.misses += 1;
            self.summary_dirty = true;
            return null;
        }

        if (!std.mem.eql(u8, header.plugin_id, plugin_id) or
            !std.mem.eql(u8, header.plugin_abi_version, plugin_abi_version) or
            !std.mem.eql(u8, header.plugin_semver, plugin_semver))
        {
            self.stats.misses += 1;
            self.summary_dirty = true;
            return null;
        }

        if (header.file_hash != file_content_hash) {
            self.stats.misses += 1;
            self.summary_dirty = true;
            return null;
        }

        // Deserialize cached data directly from file
        var nodes_len_bytes: [4]u8 = undefined;
        _ = try cache_file.readAll(&nodes_len_bytes);
        const nodes_len = std.mem.readInt(u32, &nodes_len_bytes, .little);
        const nodes = try allocator.alloc(ir.Node, nodes_len);
        errdefer allocator.free(nodes);

        for (nodes) |*node| {
            node.* = try deserializeNodeFile(allocator, cache_file);
        }

        var edges_len_bytes: [4]u8 = undefined;
        _ = try cache_file.readAll(&edges_len_bytes);
        const edges_len = std.mem.readInt(u32, &edges_len_bytes, .little);
        const edges = try allocator.alloc(ir.Edge, edges_len);
        errdefer allocator.free(edges);

        for (edges) |*edge| {
            edge.* = try deserializeEdgeFile(allocator, cache_file);
        }

        var diagnostics_len_bytes: [4]u8 = undefined;
        _ = try cache_file.readAll(&diagnostics_len_bytes);
        const diagnostics_len = std.mem.readInt(u32, &diagnostics_len_bytes, .little);
        const diagnostics = try allocator.alloc(ir.Diagnostic, diagnostics_len);
        errdefer allocator.free(diagnostics);

        for (diagnostics) |*diag| {
            diag.* = try deserializeDiagnosticFile(allocator, cache_file);
        }

        self.stats.hits += 1;
        self.summary_dirty = true;

        return CacheEntry{
            .nodes = nodes,
            .edges = edges,
            .diagnostics = diagnostics,
        };
    }

    /// Get cache statistics
    pub fn getStats(self: Self) CacheStats {
        return self.stats;
    }

    pub fn resetRunStats(self: *Self) void {
        self.stats.hits = 0;
        self.stats.misses = 0;
        self.summary_dirty = true;
    }

    pub fn refreshEntryStats(self: *Self) !void {
        const snapshot = try self.recalculateEntryStats();
        self.stats.entries = snapshot.count;
        self.stats.total_size_bytes = snapshot.bytes;
        self.summary_dirty = true;
    }

    fn recalculateEntryStats(self: *Self) !EntryStats {
        var iterator = self.cache_dir.iterate();
        var count: u32 = 0;
        var total: u64 = 0;
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".cache")) continue;

            const stat = try self.cache_dir.statFile(entry.name);
            count += 1;
            total += @as(u64, @intCast(stat.size));
        }

        return EntryStats{ .count = count, .bytes = total };
    }

    fn loadSummary(self: *Self) !void {
        const file = self.cache_dir.openFile(SUMMARY_FILENAME, .{}) catch return;
        defer file.close();

        const data = file.readToEndAlloc(self.allocator, 512) catch return;
        defer self.allocator.free(data);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch return;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return;
        const object = root.object;

        if (object.get("hits")) |hits_value| switch (hits_value) {
            .integer => |v| if (v >= 0) {
                const hits_u64: u64 = @intCast(v);
                self.stats.hits = @intCast(hits_u64);
            },
            else => {},
        };

        if (object.get("misses")) |miss_value| switch (miss_value) {
            .integer => |v| if (v >= 0) {
                const misses_u64: u64 = @intCast(v);
                self.stats.misses = @intCast(misses_u64);
            },
            else => {},
        };

        if (object.get("entries")) |entries_value| switch (entries_value) {
            .integer => |v| if (v >= 0) {
                const entries_u64: u64 = @intCast(v);
                self.stats.entries = @intCast(entries_u64);
            },
            else => {},
        };

        if (object.get("total_bytes")) |bytes_value| switch (bytes_value) {
            .integer => |v| if (v >= 0) {
                const bytes_u64: u64 = @intCast(v);
                self.stats.total_size_bytes = bytes_u64;
            },
            else => {},
        };

        self.summary_dirty = false;
    }

    fn persistSummary(self: *Self) !void {
        const file = try self.cache_dir.createFile(SUMMARY_FILENAME, .{ .truncate = true });
        defer file.close();

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"hits\":{d},\"misses\":{d},\"entries\":{d},\"total_bytes\":{d}}}\n",
            .{ self.stats.hits, self.stats.misses, self.stats.entries, self.stats.total_size_bytes },
        );
        defer self.allocator.free(payload);

        try file.writeAll(payload);
        self.summary_dirty = false;
    }

    /// Prune old cache entries
    pub fn prune(self: *Self, max_age_seconds: ?i64) !struct { removed_count: u32, freed_bytes: u64 } {
        var removed_count: u32 = 0;
        var freed_bytes: u64 = 0;
        const now = std.time.timestamp();
        const threshold_seconds: ?i64 = max_age_seconds;

        var iterator = self.cache_dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;

            if (!std.mem.endsWith(u8, entry.name, ".cache")) continue;

            const stat = try self.cache_dir.statFile(entry.name);
            const ns_per_s: i128 = @as(i128, std.time.ns_per_s);
            const mtime_ticks = @divTrunc(stat.mtime, ns_per_s);
            const mtime_seconds: i64 = @intCast(mtime_ticks);
            const file_age = now - mtime_seconds;

            if (threshold_seconds) |threshold| {
                if (threshold > 0 and file_age <= threshold) continue;
            }

            // Validate cache entry before removing
            const cache_file = try self.cache_dir.openFile(entry.name, .{});
            defer cache_file.close();

            var header_size_bytes: [8]u8 = undefined;
            _ = try cache_file.readAll(&header_size_bytes);
            const header_size = std.mem.readInt(u64, &header_size_bytes, .little);

            // Read header data
            const header_data = try self.allocator.alloc(u8, header_size);
            defer self.allocator.free(header_data);
            _ = try cache_file.readAll(header_data);

            var header_fbs = std.io.fixedBufferStream(header_data);
            var header = CacheHeader.deserialize(self.allocator, header_fbs.reader()) catch |err| {
                if (err == error.SchemaMismatch) {
                    try self.cache_dir.deleteFile(entry.name);
                    removed_count += 1;
                    freed_bytes += @as(u64, @intCast(stat.size));
                    continue;
                }
                continue;
            };
            defer header.deinit(self.allocator);

            // Remove if schema version doesn't match
            if (header.schema_version != R2M_SCHEMA_VERSION) {
                try self.cache_dir.deleteFile(entry.name);
                removed_count += 1;
                freed_bytes += @as(u64, @intCast(stat.size));
                continue;
            }

            // Remove if too old (when max_age is specified)
            if (threshold_seconds) |threshold| {
                if (threshold <= 0 or file_age > threshold) {
                    try self.cache_dir.deleteFile(entry.name);
                    removed_count += 1;
                    freed_bytes += @as(u64, @intCast(stat.size));
                }
            }
        }

        if (removed_count > 0 or freed_bytes > 0) {
            self.refreshEntryStats() catch {};
        }

        return .{ .removed_count = removed_count, .freed_bytes = freed_bytes };
    }

    /// Clear all cache entries
    pub fn clear(self: *Self) !struct { removed_count: u32, freed_bytes: u64 } {
        var removed_count: u32 = 0;
        var freed_bytes: u64 = 0;

        var iterator = self.cache_dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;

            if (!std.mem.endsWith(u8, entry.name, ".cache")) continue;

            const stat = try self.cache_dir.statFile(entry.name);
            try self.cache_dir.deleteFile(entry.name);
            removed_count += 1;
            freed_bytes += @as(u64, @intCast(stat.size));
        }

        // Reset stats
        self.stats.entries = 0;
        self.stats.total_size_bytes = 0;
        self.stats.hits = 0;
        self.stats.misses = 0;
        self.summary_dirty = true;

        return .{ .removed_count = removed_count, .freed_bytes = freed_bytes };
    }

    // Serialization helpers
    fn serializeNode(writer: anytype, node: ir.Node) !void {
        try writeString(writer, node.id);
        try writeString(writer, node.lang);
        try writer.writeInt(u32, @intFromEnum(node.kind), .little);
        try writeString(writer, node.name);
        try writeString(writer, node.fqname);
        try writeString(writer, node.file);
        try writeRange(writer, node.range);
        try writeOptionalString(writer, node.signature);
        try writer.writeInt(u32, @intFromEnum(node.visibility), .little);
        try writeString(writer, node.origin_plugin);
        try writeOptionalString(writer, node.module_id);
        try writeStringArray(writer, node.tags);
    }

    fn serializeEdge(writer: anytype, edge: ir.Edge) !void {
        try writeString(writer, edge.src);
        try writeString(writer, edge.dst);
        try writer.writeInt(u32, @intFromEnum(edge.rel), .little);
        try writer.writeInt(u32, @intFromEnum(edge.certainty), .little);
        try writeOptionalString(writer, edge.certainty_reason);
        try writeStringArray(writer, edge.evidence_paths);
        try writeU32Array(writer, edge.evidence_lines);
        try writeDiagnosticRefArray(writer, edge.diagnostics);
    }

    fn serializeDiagnostic(writer: anytype, diag: ir.Diagnostic) !void {
        try writeString(writer, diag.id);
        try writer.writeInt(u32, @intFromEnum(diag.severity), .little);
        try writeString(writer, diag.message);
        try writeString(writer, diag.file);
        try writeRange(writer, diag.range);
        try writeStringArray(writer, diag.tags);
    }

    // File-based deserialization helpers
    fn deserializeNodeFile(allocator: std.mem.Allocator, file: std.fs.File) !ir.Node {
        return ir.Node{
            .id = try readStringFile(allocator, file),
            .lang = try readStringFile(allocator, file),
            .kind = @enumFromInt(try readIntU32File(file)),
            .name = try readStringFile(allocator, file),
            .fqname = try readStringFile(allocator, file),
            .file = try readStringFile(allocator, file),
            .range = try readRangeFile(file),
            .signature = try readOptionalStringFile(allocator, file),
            .visibility = @enumFromInt(try readIntU32File(file)),
            .origin_plugin = try readStringFile(allocator, file),
            .module_id = try readOptionalStringFile(allocator, file),
            .tags = try readStringArrayFile(allocator, file),
        };
    }

    fn deserializeEdgeFile(allocator: std.mem.Allocator, file: std.fs.File) !ir.Edge {
        return ir.Edge{
            .src = try readStringFile(allocator, file),
            .dst = try readStringFile(allocator, file),
            .rel = @enumFromInt(try readIntU32File(file)),
            .certainty = @enumFromInt(try readIntU32File(file)),
            .certainty_reason = try readOptionalStringFile(allocator, file),
            .evidence_paths = try readStringArrayFile(allocator, file),
            .evidence_lines = try readU32ArrayFile(allocator, file),
            .diagnostics = try readDiagnosticRefArrayFile(allocator, file),
        };
    }

    fn deserializeDiagnosticFile(allocator: std.mem.Allocator, file: std.fs.File) !ir.Diagnostic {
        return ir.Diagnostic{
            .id = try readStringFile(allocator, file),
            .severity = @enumFromInt(try readIntU32File(file)),
            .message = try readStringFile(allocator, file),
            .file = try readStringFile(allocator, file),
            .range = try readRangeFile(file),
            .tags = try readStringArrayFile(allocator, file),
        };
    }

    // Basic serialization helpers
    fn writeString(writer: anytype, str: []const u8) !void {
        try writer.writeInt(u32, @intCast(str.len), .little);
        try writer.writeAll(str);
    }

    fn writeOptionalString(writer: anytype, str: ?[]const u8) !void {
        if (str) |s| {
            try writer.writeInt(u8, 1, .little);
            try writeString(writer, s);
        } else {
            try writer.writeInt(u8, 0, .little);
        }
    }

    fn writeStringArray(writer: anytype, arr: []const []const u8) !void {
        try writer.writeInt(u32, @intCast(arr.len), .little);
        for (arr) |str| {
            try writeString(writer, str);
        }
    }

    fn writeU32Array(writer: anytype, arr: []const u32) !void {
        try writer.writeInt(u32, @intCast(arr.len), .little);
        for (arr) |val| {
            try writer.writeInt(u32, val, .little);
        }
    }

    fn writeDiagnosticRefArray(writer: anytype, arr: []const ir.DiagnosticRef) !void {
        try writer.writeInt(u32, @intCast(arr.len), .little);
        for (arr) |ref| {
            try writeString(writer, ref.id);
        }
    }

    fn writeRange(writer: anytype, range: ir.Range) !void {
        try writer.writeInt(u32, range.start.line, .little);
        try writer.writeInt(u32, range.start.column, .little);
        try writer.writeInt(u32, range.end.line, .little);
        try writer.writeInt(u32, range.end.column, .little);
    }

    // File-based reading helpers
    fn readIntU32File(file: std.fs.File) !u32 {
        var bytes: [4]u8 = undefined;
        _ = try file.readAll(&bytes);
        return std.mem.readInt(u32, &bytes, .little);
    }

    fn readStringFile(allocator: std.mem.Allocator, file: std.fs.File) ![]const u8 {
        var len_bytes: [4]u8 = undefined;
        _ = try file.readAll(&len_bytes);
        const len = std.mem.readInt(u32, &len_bytes, .little);
        const str = try allocator.alloc(u8, len);
        _ = try file.readAll(str);
        return str;
    }

    fn readOptionalStringFile(allocator: std.mem.Allocator, file: std.fs.File) !?[]const u8 {
        var has_value_byte: [1]u8 = undefined;
        _ = try file.readAll(&has_value_byte);
        const has_value = has_value_byte[0];
        if (has_value == 1) {
            return try readStringFile(allocator, file);
        }
        return null;
    }

    fn readStringArrayFile(allocator: std.mem.Allocator, file: std.fs.File) ![][]const u8 {
        var len_bytes: [4]u8 = undefined;
        _ = try file.readAll(&len_bytes);
        const len = std.mem.readInt(u32, &len_bytes, .little);
        const arr = try allocator.alloc([]const u8, len);
        for (arr) |*str| {
            str.* = try readStringFile(allocator, file);
        }
        return arr;
    }

    fn readU32ArrayFile(allocator: std.mem.Allocator, file: std.fs.File) ![]u32 {
        var len_bytes: [4]u8 = undefined;
        _ = try file.readAll(&len_bytes);
        const len = std.mem.readInt(u32, &len_bytes, .little);
        const arr = try allocator.alloc(u32, len);
        for (arr) |*val| {
            var val_bytes: [4]u8 = undefined;
            _ = try file.readAll(&val_bytes);
            val.* = std.mem.readInt(u32, &val_bytes, .little);
        }
        return arr;
    }

    fn readDiagnosticRefArrayFile(allocator: std.mem.Allocator, file: std.fs.File) ![]ir.DiagnosticRef {
        var len_bytes: [4]u8 = undefined;
        _ = try file.readAll(&len_bytes);
        const len = std.mem.readInt(u32, &len_bytes, .little);
        const arr = try allocator.alloc(ir.DiagnosticRef, len);
        for (arr) |*ref| {
            ref.* = ir.DiagnosticRef{
                .id = try readStringFile(allocator, file),
            };
        }
        return arr;
    }

    fn readRangeFile(file: std.fs.File) !ir.Range {
        var line_bytes: [4]u8 = undefined;
        var column_bytes: [4]u8 = undefined;

        _ = try file.readAll(&line_bytes);
        _ = try file.readAll(&column_bytes);
        const start_line = std.mem.readInt(u32, &line_bytes, .little);
        const start_column = std.mem.readInt(u32, &column_bytes, .little);

        _ = try file.readAll(&line_bytes);
        _ = try file.readAll(&column_bytes);
        const end_line = std.mem.readInt(u32, &line_bytes, .little);
        const end_column = std.mem.readInt(u32, &column_bytes, .little);

        return ir.Range{
            .start = .{
                .line = start_line,
                .column = start_column,
            },
            .end = .{
                .line = end_line,
                .column = end_column,
            },
        };
    }
};
