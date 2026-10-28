const std = @import("std");
const ir = @import("ir");
const diag = @import("diag");

/// Grouping strategies for organizing graph nodes
pub const GroupingStrategy = enum {
    /// Group by package/module (based on module_id or file path)
    Package,
    /// Group by directory structure
    Directory,
    /// Group by node type (func, type, var, etc.)
    NodeType,
    /// Group by language (zig, typescript, c, etc.)
    Language,
    /// Hybrid: primary by language, secondary by package
    HybridLanguagePackage,
    /// Hybrid: primary by directory, secondary by language
    HybridDirectoryLanguage,
    /// No grouping (flat structure)
    None,
};

/// Grouping configuration
pub const GroupingConfig = struct {
    /// Primary grouping strategy
    primary: GroupingStrategy = .Package,
    /// Optional secondary grouping strategy
    secondary: ?GroupingStrategy = null,
    /// Maximum group size before splitting
    max_group_size: usize = 50,
    /// Whether to create group nodes in the graph
    create_group_nodes: bool = true,
    /// Custom grouping function (optional)
    custom_group_fn: ?*const fn (node: ir.Node) []const u8 = null,
};

/// Graph group containing related nodes
pub const GraphGroup = struct {
    id: []const u8,
    name: []const u8,
    kind: GroupingStrategy,
    nodes: []const []const u8, // Node IDs
    subgroups: []GraphGroup,
    metadata: std.StringHashMap([]const u8),

    pub fn deinit(self: *GraphGroup, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.nodes);

        for (self.subgroups) |*subgroup| {
            subgroup.deinit(allocator);
        }
        allocator.free(self.subgroups);

        var metadata_iter = self.metadata.iterator();
        while (metadata_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }
};

/// Grouping engine for organizing graph nodes
pub const GroupingEngine = struct {
    allocator: std.mem.Allocator,
    config: GroupingConfig,

    pub fn init(allocator: std.mem.Allocator, config: GroupingConfig) GroupingEngine {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Apply grouping strategy to nodes
    pub fn groupNodes(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        switch (self.config.primary) {
            .Package => return self.groupByPackage(nodes),
            .Directory => return self.groupByDirectory(nodes),
            .NodeType => return self.groupByNodeType(nodes),
            .Language => return self.groupByLanguage(nodes),
            .HybridLanguagePackage => return self.groupByHybridLanguagePackage(nodes),
            .HybridDirectoryLanguage => return self.groupByHybridDirectoryLanguage(nodes),
            .None => return self.groupFlat(nodes),
        }
    }

    /// Group nodes by package/module
    fn groupByPackage(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        var package_map = std.StringHashMap(std.ArrayList([]const u8)).init(self.allocator);
        defer {
            var iter = package_map.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            package_map.deinit();
        }

        // Group nodes by package
        for (nodes) |node| {
            const package_name = self.extractPackageName(node);
            const entry = try package_map.getOrPut(package_name);
            if (!entry.found_existing) {
                entry.value_ptr.* = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
            }
            try entry.value_ptr.append(self.allocator, node.id);
        }

        // Convert to groups
        var groups = try self.allocator.alloc(GraphGroup, package_map.count());
        var group_idx: usize = 0;

        var iter = package_map.iterator();
        while (iter.next()) |entry| {
            const package_name = entry.key_ptr.*;
            const node_ids = try entry.value_ptr.toOwnedSlice(self.allocator);

            // Apply secondary grouping if configured
            var subgroups = try std.ArrayList(GraphGroup).initCapacity(self.allocator, 0);
            // TODO: Fix secondary grouping error set inference
            // if (self.config.secondary) |secondary| {
            //     const sub_nodes = try self.getNodesByIds(nodes, node_ids);
            //     defer self.allocator.free(sub_nodes);
            //
            //     const temp_config = GroupingConfig{
            //         .primary = secondary,
            //         .secondary = null,
            //         .max_group_size = self.config.max_group_size,
            //         .create_group_nodes = false,
            //     };
            //     const temp_engine = GroupingEngine.init(self.allocator, temp_config);
            //     const temp_groups = try temp_engine.groupNodes(sub_nodes);
            //     defer {
            //         for (temp_groups) |*group| {
            //             group.deinit(self.allocator);
            //         }
            //         self.allocator.free(temp_groups);
            //     }
            //
            //     try subgroups.appendSlice(temp_groups);
            // }

            groups[group_idx] = GraphGroup{
                .id = try self.allocator.dupe(u8, package_name),
                .name = try self.allocator.dupe(u8, package_name),
                .kind = .Package,
                .nodes = node_ids,
                .subgroups = subgroups.toOwnedSlice(self.allocator) catch &[_]GraphGroup{},
                .metadata = std.StringHashMap([]const u8).init(self.allocator),
            };

            group_idx += 1;
        }

        return groups;
    }

    /// Group nodes by directory structure
    fn groupByDirectory(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        var dir_map = std.StringHashMap(std.ArrayList([]const u8)).init(self.allocator);
        defer {
            var iter = dir_map.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            dir_map.deinit();
        }

        // Group nodes by directory
        for (nodes) |node| {
            const dir_path = std.fs.path.dirname(node.file) orelse "";
            const entry = try dir_map.getOrPut(dir_path);
            if (!entry.found_existing) {
                entry.value_ptr.* = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
            }
            try entry.value_ptr.append(self.allocator, node.id);
        }

        // Convert to groups
        var groups = try self.allocator.alloc(GraphGroup, dir_map.count());
        var group_idx: usize = 0;

        var iter = dir_map.iterator();
        while (iter.next()) |entry| {
            const dir_path = entry.key_ptr.*;
            const node_ids = try entry.value_ptr.toOwnedSlice(self.allocator);

            const group_name = if (dir_path.len == 0) "root" else std.fs.path.basename(dir_path);

            groups[group_idx] = GraphGroup{
                .id = try std.fmt.allocPrint(self.allocator, "dir_{d}", .{group_idx}),
                .name = try self.allocator.dupe(u8, group_name),
                .kind = .Directory,
                .nodes = node_ids,
                .subgroups = &[_]GraphGroup{},
                .metadata = std.StringHashMap([]const u8).init(self.allocator),
            };

            // Add directory path metadata
            try groups[group_idx].metadata.put("path", try self.allocator.dupe(u8, dir_path));

            group_idx += 1;
        }

        return groups;
    }

    /// Group nodes by node type
    fn groupByNodeType(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        const type_count = @typeInfo(ir.NodeKind).@"enum".fields.len;
        var type_arrays = try self.allocator.alloc(std.ArrayList([]const u8), type_count);
        defer self.allocator.free(type_arrays);

        for (type_arrays) |*array| {
            array.* = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        }

        // Group nodes by type
        for (nodes) |node| {
            const type_idx = @intFromEnum(node.kind);
            try type_arrays[type_idx].append(self.allocator, node.id);
        }

        // Convert to groups (only for non-empty types)
        var group_count: usize = 0;
        for (type_arrays) |array| {
            if (array.items.len > 0) group_count += 1;
        }

        var groups = try self.allocator.alloc(GraphGroup, group_count);
        var group_idx: usize = 0;

        for (type_arrays, 0..) |*array, i| {
            if (array.items.len == 0) continue;

            const node_type = @as(ir.NodeKind, @enumFromInt(i));
            const node_ids = try array.toOwnedSlice(self.allocator);

            groups[group_idx] = GraphGroup{
                .id = try std.fmt.allocPrint(self.allocator, "type_{s}", .{node_type.toString()}),
                .name = try self.allocator.dupe(u8, node_type.toString()),
                .kind = .NodeType,
                .nodes = node_ids,
                .subgroups = &[_]GraphGroup{},
                .metadata = std.StringHashMap([]const u8).init(self.allocator),
            };

            group_idx += 1;
        }

        return groups;
    }

    /// Group nodes by language
    fn groupByLanguage(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        var lang_map = std.StringHashMap(std.ArrayList([]const u8)).init(self.allocator);
        defer {
            var iter = lang_map.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            lang_map.deinit();
        }

        // Group nodes by language
        for (nodes) |node| {
            const entry = try lang_map.getOrPut(node.lang);
            if (!entry.found_existing) {
                entry.value_ptr.* = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
            }
            try entry.value_ptr.append(self.allocator, node.id);
        }

        // Convert to groups
        var groups = try self.allocator.alloc(GraphGroup, lang_map.count());
        var group_idx: usize = 0;

        var iter = lang_map.iterator();
        while (iter.next()) |entry| {
            const lang = entry.key_ptr.*;
            const node_ids = try entry.value_ptr.toOwnedSlice(self.allocator);

            groups[group_idx] = GraphGroup{
                .id = try std.fmt.allocPrint(self.allocator, "lang_{s}", .{lang}),
                .name = try self.allocator.dupe(u8, lang),
                .kind = .Language,
                .nodes = node_ids,
                .subgroups = &[_]GraphGroup{},
                .metadata = std.StringHashMap([]const u8).init(self.allocator),
            };

            group_idx += 1;
        }

        return groups;
    }

    /// Flat grouping (no actual grouping)
    fn groupFlat(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        if (nodes.len == 0) return &[_]GraphGroup{};

        const node_ids = try self.allocator.alloc([]const u8, nodes.len);
        for (nodes, 0..) |node, i| {
            node_ids[i] = node.id;
        }

        const groups = try self.allocator.alloc(GraphGroup, 1);
        groups[0] = GraphGroup{
            .id = try self.allocator.dupe(u8, "flat"),
            .name = try self.allocator.dupe(u8, "all"),
            .kind = .None,
            .nodes = node_ids,
            .subgroups = &[_]GraphGroup{},
            .metadata = std.StringHashMap([]const u8).init(self.allocator),
        };

        return groups;
    }

    /// Extract package name from node
    fn extractPackageName(self: *const GroupingEngine, node: ir.Node) []const u8 {
        _ = self;
        // Use module_id if available
        if (node.module_id) |module_id| {
            return module_id;
        }

        // Extract from fqname (take first component before dot)
        if (std.mem.indexOf(u8, node.fqname, ".")) |dot_pos| {
            return node.fqname[0..dot_pos];
        }

        // Use node name as fallback
        return node.name;
    }

    /// Get nodes by their IDs
    fn getNodesByIds(self: *const GroupingEngine, all_nodes: []const ir.Node, node_ids: []const []const u8) ![]ir.Node {
        var nodes = try self.allocator.alloc(ir.Node, node_ids.len);
        var found_count: usize = 0;

        for (node_ids) |node_id| {
            for (all_nodes) |node| {
                if (std.mem.eql(u8, node.id, node_id)) {
                    nodes[found_count] = node;
                    found_count += 1;
                    break;
                }
            }
        }

        return nodes[0..found_count];
    }

    /// Apply size limits to groups (split large groups)
    pub fn applySizeLimits(self: *const GroupingEngine, groups: []GraphGroup) ![]GraphGroup {
        var result = try std.ArrayList(GraphGroup).initCapacity(self.allocator, 0);

        for (groups) |group| {
            if (group.nodes.len <= self.config.max_group_size) {
                // Group is within limits, keep as is
                const group_copy = try self.cloneGroup(group);
                try result.append(self.allocator, group_copy);
            } else {
                // Split large group
                const split_groups = try self.splitGroup(group);
                try result.appendSlice(split_groups);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Clone a group (deep copy)
    fn cloneGroup(self: *const GroupingEngine, original: GraphGroup) !GraphGroup {
        return GraphGroup{
            .id = try self.allocator.dupe(u8, original.id),
            .name = try self.allocator.dupe(u8, original.name),
            .kind = original.kind,
            .nodes = try self.allocator.dupe([]const u8, original.nodes),
            .subgroups = try self.allocator.dupe(GraphGroup, original.subgroups),
            .metadata = std.StringHashMap([]const u8).init(self.allocator),
        };
    }

    /// Split a large group into smaller groups
    fn splitGroup(self: *const GroupingEngine, group: GraphGroup) ![]GraphGroup {
        const chunk_size = self.config.max_group_size;
        const chunk_count = (group.nodes.len + chunk_size - 1) / chunk_size;

        var split_groups = try self.allocator.alloc(GraphGroup, chunk_count);

        for (0..chunk_count) |i| {
            const start = i * chunk_size;
            const end = @min(start + chunk_size, group.nodes.len);
            const chunk_nodes = group.nodes[start..end];

            split_groups[i] = GraphGroup{
                .id = try std.fmt.allocPrint(self.allocator, "{s}_part_{d}", .{ group.id, i }),
                .name = try std.fmt.allocPrint(self.allocator, "{s} (part {d})", .{ group.name, i + 1 }),
                .kind = group.kind,
                .nodes = try self.allocator.dupe([]const u8, chunk_nodes),
                .subgroups = &[_]GraphGroup{},
                .metadata = std.StringHashMap([]const u8).init(self.allocator),
            };
        }

        return split_groups;
    }

    /// Group by hybrid language + package strategy
    fn groupByHybridLanguagePackage(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        // First group by language
        const lang_groups = try self.groupByLanguage(nodes);
        defer {
            for (lang_groups) |*group| {
                group.deinit(self.allocator);
            }
            self.allocator.free(lang_groups);
        }

        // Then create subgroups by package within each language
        var all_groups = std.ArrayList(GraphGroup).initCapacity(self.allocator, 10) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer all_groups.deinit(self.allocator);

        for (lang_groups) |lang_group| {
            const lang_nodes = try self.getNodesByIds(nodes, lang_group.nodes);
            defer self.allocator.free(lang_nodes);

            const temp_config = GroupingConfig{
                .primary = .Package,
                .secondary = null,
                .max_group_size = self.config.max_group_size,
                .create_group_nodes = false,
            };
            const temp_engine = GroupingEngine.init(self.allocator, temp_config);
            const package_groups = try temp_engine.groupByPackage(lang_nodes);
            defer {
                for (package_groups) |*group| {
                    group.deinit(self.allocator);
                }
                self.allocator.free(package_groups);
            }

            // Create hybrid groups with language as parent
            for (package_groups) |pkg_group| {
                const hybrid_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ lang_group.name, pkg_group.name });
                const hybrid_id = try std.fmt.allocPrint(self.allocator, "{s}_{s}", .{ lang_group.id, pkg_group.id });

                var hybrid_group = GraphGroup{
                    .id = hybrid_id,
                    .name = hybrid_name,
                    .kind = .HybridLanguagePackage,
                    .nodes = try self.allocator.dupe([]const u8, pkg_group.nodes),
                    .subgroups = &[_]GraphGroup{},
                    .metadata = std.StringHashMap([]const u8).init(self.allocator),
                };

                // Add metadata
                try hybrid_group.metadata.put("language", try self.allocator.dupe(u8, lang_group.name));
                try hybrid_group.metadata.put("package", try self.allocator.dupe(u8, pkg_group.name));

                try all_groups.append(self.allocator, hybrid_group);
            }
        }

        return all_groups.toOwnedSlice(self.allocator);
    }

    /// Group by hybrid directory + language strategy
    fn groupByHybridDirectoryLanguage(self: *const GroupingEngine, nodes: []const ir.Node) ![]GraphGroup {
        // First group by directory
        const dir_groups = try self.groupByDirectory(nodes);
        defer {
            for (dir_groups) |*group| {
                group.deinit(self.allocator);
            }
            self.allocator.free(dir_groups);
        }

        // Then create subgroups by language within each directory
        var all_groups = std.ArrayList(GraphGroup).initCapacity(self.allocator, 10) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer all_groups.deinit(self.allocator);

        for (dir_groups) |dir_group| {
            const dir_nodes = try self.getNodesByIds(nodes, dir_group.nodes);
            defer self.allocator.free(dir_nodes);

            const temp_config = GroupingConfig{
                .primary = .Language,
                .secondary = null,
                .max_group_size = self.config.max_group_size,
                .create_group_nodes = false,
            };
            const temp_engine = GroupingEngine.init(self.allocator, temp_config);
            const lang_groups = try temp_engine.groupByLanguage(dir_nodes);
            defer {
                for (lang_groups) |*group| {
                    group.deinit(self.allocator);
                }
                self.allocator.free(lang_groups);
            }

            // Create hybrid groups with directory as parent
            for (lang_groups) |lang_group| {
                const hybrid_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_group.name, lang_group.name });
                const hybrid_id = try std.fmt.allocPrint(self.allocator, "{s}_{s}", .{ dir_group.id, lang_group.id });

                var hybrid_group = GraphGroup{
                    .id = hybrid_id,
                    .name = hybrid_name,
                    .kind = .HybridDirectoryLanguage,
                    .nodes = try self.allocator.dupe([]const u8, lang_group.nodes),
                    .subgroups = &[_]GraphGroup{},
                    .metadata = std.StringHashMap([]const u8).init(self.allocator),
                };

                // Add metadata
                try hybrid_group.metadata.put("directory", try self.allocator.dupe(u8, dir_group.name));
                try hybrid_group.metadata.put("language", try self.allocator.dupe(u8, lang_group.name));

                try all_groups.append(self.allocator, hybrid_group);
            }
        }

        return all_groups.toOwnedSlice(self.allocator);
    }
};
