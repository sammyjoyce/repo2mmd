const std = @import("std");
const ir = @import("ir");
const diag = @import("diag");

/// Pruning strategies for reducing graph complexity
pub const PruningStrategy = enum {
    /// Remove nodes with degree below threshold
    DegreeThreshold,
    /// Limit graph depth from entry points
    DepthLimit,
    /// Keep only reachable from entry points
    EntryPointSlicing,
    /// Remove nodes with low importance scores
    ImportanceScore,
    /// Hybrid: combine degree threshold with importance scoring
    HybridDegreeImportance,
    /// Language-aware: preserve cross-language edges
    LanguageAware,
    /// No pruning
    None,
};

/// Pruning configuration
pub const PruningConfig = struct {
    /// Primary pruning strategy
    primary: PruningStrategy = .DegreeThreshold,
    /// Minimum degree threshold (nodes with fewer connections are removed)
    min_degree: u32 = 1,
    /// Maximum depth from entry points
    max_depth: u32 = 5,
    /// Entry point node IDs for slicing
    entry_points: []const []const u8 = &[_][]const u8{},
    /// Importance score threshold (0.0-1.0)
    min_importance: f32 = 0.1,
    /// Maximum number of nodes to keep
    max_nodes: ?u32 = null,
    /// Whether to preserve connectivity
    preserve_connectivity: bool = true,
};

/// Pruning statistics
pub const PruningStats = struct {
    original_nodes: u32,
    original_edges: u32,
    pruned_nodes: u32,
    pruned_edges: u32,
    remaining_nodes: u32,
    remaining_edges: u32,
    pruning_rate: f32,
};

/// Common result type for pruning operations
const PruningResult = struct {
    nodes: []const ir.Node,
    edges: []const ir.Edge,
};

/// Pruning engine for reducing graph complexity
pub const PruningEngine = struct {
    allocator: std.mem.Allocator,
    config: PruningConfig,

    pub fn init(allocator: std.mem.Allocator, config: PruningConfig) PruningEngine {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Apply pruning strategy to graph
    pub fn pruneGraph(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge) !struct {
        result: PruningResult,
        stats: PruningStats,
    } {
        const original_node_count = @as(u32, @intCast(nodes.len));
        const original_edge_count = @as(u32, @intCast(edges.len));

        var pruned_nodes = nodes;
        var pruned_edges = edges;

        // Apply primary pruning strategy
        switch (self.config.primary) {
            .DegreeThreshold => {
                const result = try self.pruneByDegree(pruned_nodes, pruned_edges);
                pruned_nodes = result.nodes;
                pruned_edges = result.edges;
            },
            .DepthLimit => {
                const result = try self.pruneByDepth(pruned_nodes, pruned_edges);
                pruned_nodes = result.nodes;
                pruned_edges = result.edges;
            },
            .EntryPointSlicing => {
                const result = try self.pruneByEntryPoints(pruned_nodes, pruned_edges);
                pruned_nodes = result.nodes;
                pruned_edges = result.edges;
            },
            .ImportanceScore => {
                const result = try self.pruneByImportance(pruned_nodes, pruned_edges);
                pruned_nodes = result.nodes;
                pruned_edges = result.edges;
            },
            .HybridDegreeImportance => {
                const result = try self.pruneByHybridDegreeImportance(pruned_nodes, pruned_edges);
                pruned_nodes = result.nodes;
                pruned_edges = result.edges;
            },
            .LanguageAware => {
                const result = try self.pruneByLanguageAware(pruned_nodes, pruned_edges);
                pruned_nodes = result.nodes;
                pruned_edges = result.edges;
            },
            .None => {
                // No pruning
            },
        }

        // Apply node count limit if specified
        if (self.config.max_nodes) |max_nodes| {
            if (pruned_nodes.len > max_nodes) {
                const result = try self.limitNodeCount(pruned_nodes, pruned_edges, max_nodes);
                pruned_nodes = result.nodes;
                pruned_edges = result.edges;
            }
        }

        const pruned_node_count = @as(u32, @intCast(pruned_nodes.len));
        const pruned_edge_count = @as(u32, @intCast(pruned_edges.len));

        const stats = PruningStats{
            .original_nodes = original_node_count,
            .original_edges = original_edge_count,
            .pruned_nodes = original_node_count - pruned_node_count,
            .pruned_edges = original_edge_count - pruned_edge_count,
            .remaining_nodes = pruned_node_count,
            .remaining_edges = pruned_edge_count,
            .pruning_rate = if (original_node_count > 0)
                @as(f32, @floatFromInt(original_node_count - pruned_node_count)) / @as(f32, @floatFromInt(original_node_count)) * 100.0
            else
                0.0,
        };

        return .{
            .result = .{
                .nodes = pruned_nodes,
                .edges = pruned_edges,
            },
            .stats = stats,
        };
    }

    /// Prune nodes by degree threshold
    fn pruneByDegree(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge) !PruningResult {
        // Calculate node degrees
        var node_degrees = std.StringHashMap(u32).init(self.allocator);
        defer node_degrees.deinit();

        // Initialize degrees
        for (nodes) |node| {
            try node_degrees.put(node.id, 0);
        }

        // Count degrees from edges
        for (edges) |edge| {
            if (node_degrees.getPtr(edge.src)) |degree| {
                degree.* += 1;
            }
            if (node_degrees.getPtr(edge.dst)) |degree| {
                degree.* += 1;
            }
        }

        // Filter nodes by degree threshold
        var kept_nodes = try std.ArrayList(ir.Node).initCapacity(self.allocator, 0);
        defer kept_nodes.deinit(self.allocator);

        var kept_node_ids = std.StringHashMap(void).init(self.allocator);
        defer kept_node_ids.deinit();

        for (nodes) |node| {
            if (node_degrees.get(node.id)) |degree| {
                if (degree >= self.config.min_degree) {
                    try kept_nodes.append(self.allocator, node);
                    try kept_node_ids.put(node.id, {});
                }
            }
        }

        // Filter edges to keep only those between kept nodes
        var kept_edges = try std.ArrayList(ir.Edge).initCapacity(self.allocator, 0);
        defer kept_edges.deinit(self.allocator);

        for (edges) |edge| {
            if (kept_node_ids.contains(edge.src) and kept_node_ids.contains(edge.dst)) {
                try kept_edges.append(self.allocator, edge);
            }
        }

        return PruningResult{
            .nodes = try kept_nodes.toOwnedSlice(self.allocator),
            .edges = try kept_edges.toOwnedSlice(self.allocator),
        };
    }

    /// Prune nodes by depth from entry points
    fn pruneByDepth(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge) !PruningResult {
        if (self.config.entry_points.len == 0) {
            // If no entry points specified, use all nodes as entry points
            return self.pruneByDepthFromMultiple(nodes, edges, nodes);
        }

        // Find entry point nodes
        var entry_nodes = try std.ArrayList(ir.Node).initCapacity(self.allocator, 0);
        defer entry_nodes.deinit(self.allocator);

        var entry_node_ids = std.StringHashMap(void).init(self.allocator);
        defer entry_node_ids.deinit();

        for (self.config.entry_points) |entry_id| {
            for (nodes) |node| {
                if (std.mem.eql(u8, node.id, entry_id)) {
                    try entry_nodes.append(self.allocator, node);
                    try entry_node_ids.put(node.id, {});
                    break;
                }
            }
        }

        if (entry_nodes.items.len == 0) {
            // No entry points found, return original graph
            return .{
                .nodes = nodes,
                .edges = edges,
            };
        }

        return self.pruneByDepthFromMultiple(nodes, edges, entry_nodes.items);
    }

    /// Prune by depth from multiple entry nodes
    fn pruneByDepthFromMultiple(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge, entry_nodes: []const ir.Node) !PruningResult {
        // Build adjacency list
        var adjacency = std.StringHashMap(std.ArrayList([]const u8)).init(self.allocator);
        defer {
            var iter = adjacency.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            adjacency.deinit();
        }

        // Initialize adjacency list
        for (nodes) |node| {
            try adjacency.put(node.id, try std.ArrayList([]const u8).initCapacity(self.allocator, 0));
        }

        // Build adjacency from edges
        for (edges) |edge| {
            if (adjacency.getPtr(edge.src)) |neighbors| {
                try neighbors.append(self.allocator, edge.dst);
            }
        }

        // BFS from entry points to find reachable nodes within depth limit
        var visited = std.StringHashMap(u32).init(self.allocator);
        defer visited.deinit();

        var queue = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer queue.deinit(self.allocator);

        // Initialize queue with entry points
        for (entry_nodes) |entry_node| {
            try queue.append(self.allocator, entry_node.id);
            try visited.put(entry_node.id, 0); // depth 0
        }

        var front: usize = 0;
        while (front < queue.items.len) {
            const current_id = queue.items[front];
            front += 1;

            const current_depth = visited.get(current_id).?;

            if (current_depth >= self.config.max_depth) {
                continue;
            }

            if (adjacency.get(current_id)) |neighbors| {
                for (neighbors.items) |neighbor_id| {
                    if (!visited.contains(neighbor_id)) {
                        try visited.put(neighbor_id, current_depth + 1);
                        try queue.append(self.allocator, neighbor_id);
                    }
                }
            }
        }

        // Filter nodes by visited set
        var kept_nodes = try std.ArrayList(ir.Node).initCapacity(self.allocator, 0);
        defer kept_nodes.deinit(self.allocator);

        for (nodes) |node| {
            if (visited.contains(node.id)) {
                try kept_nodes.append(self.allocator, node);
            }
        }

        // Filter edges
        var kept_edges = try std.ArrayList(ir.Edge).initCapacity(self.allocator, 0);
        defer kept_edges.deinit(self.allocator);

        for (edges) |edge| {
            if (visited.contains(edge.src) and visited.contains(edge.dst)) {
                try kept_edges.append(self.allocator, edge);
            }
        }

        return PruningResult{
            .nodes = try kept_nodes.toOwnedSlice(self.allocator),
            .edges = try kept_edges.toOwnedSlice(self.allocator),
        };
    }

    /// Prune by entry point slicing (keep only reachable from entry points)
    fn pruneByEntryPoints(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge) !PruningResult {
        // Use depth limit with very high limit to get all reachable nodes
        const temp_config = PruningConfig{
            .primary = .DepthLimit,
            .max_depth = 1000, // Very high limit
            .entry_points = self.config.entry_points,
        };
        const temp_engine = PruningEngine.init(self.allocator, temp_config);
        return temp_engine.pruneByDepth(nodes, edges);
    }

    /// Prune by importance score
    fn pruneByImportance(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge) !PruningResult {
        // Calculate importance scores for nodes
        var node_scores = std.StringHashMap(f32).init(self.allocator);
        defer node_scores.deinit();

        for (nodes) |node| {
            const score = self.calculateImportanceScore(node, nodes, edges);
            try node_scores.put(node.id, score);
        }

        // Filter nodes by importance threshold
        var kept_nodes = try std.ArrayList(ir.Node).initCapacity(self.allocator, 0);
        defer kept_nodes.deinit(self.allocator);

        var kept_node_ids = std.StringHashMap(void).init(self.allocator);
        defer kept_node_ids.deinit();

        for (nodes) |node| {
            if (node_scores.get(node.id)) |score| {
                if (score >= self.config.min_importance) {
                    try kept_nodes.append(self.allocator, node);
                    try kept_node_ids.put(node.id, {});
                }
            }
        }

        // Filter edges
        var kept_edges = try std.ArrayList(ir.Edge).initCapacity(self.allocator, 0);
        defer kept_edges.deinit(self.allocator);

        for (edges) |edge| {
            if (kept_node_ids.contains(edge.src) and kept_node_ids.contains(edge.dst)) {
                try kept_edges.append(self.allocator, edge);
            }
        }

        return PruningResult{
            .nodes = try kept_nodes.toOwnedSlice(self.allocator),
            .edges = try kept_edges.toOwnedSlice(self.allocator),
        };
    }

    /// Calculate importance score for a node
    fn calculateImportanceScore(self: *const PruningEngine, node: ir.Node, all_nodes: []const ir.Node, all_edges: []const ir.Edge) f32 {
        _ = self;
        _ = all_nodes;

        var score: f32 = 0.0;

        // Base score by node type
        switch (node.kind) {
            .Func => score += 0.8,
            .Type => score += 0.6,
            .Module => score += 0.9,
            .Var => score += 0.3,
            .File => score += 0.4,
        }

        // Count connections
        var connections: u32 = 0;
        for (all_edges) |edge| {
            if (std.mem.eql(u8, edge.src, node.id) or std.mem.eql(u8, edge.dst, node.id)) {
                connections += 1;
            }
        }

        // Add connection score (normalized)
        const max_connections = 100;
        const connection_score = @min(@as(f32, @floatFromInt(connections)) / @as(f32, @floatFromInt(max_connections)), 1.0);
        score += connection_score * 0.5;

        // Visibility bonus
        switch (node.visibility) {
            .Public => score += 0.3,
            .Package => score += 0.2,
            .Private => score += 0.0,
        }

        return @min(score, 1.0);
    }

    /// Limit node count by keeping most important nodes
    fn limitNodeCount(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge, max_nodes: u32) !struct {
        nodes: []const ir.Node,
        edges: []const ir.Edge,
    } {
        if (nodes.len <= max_nodes) {
            return .{
                .nodes = nodes,
                .edges = edges,
            };
        }

        // Calculate importance scores
        const ScoredNode = struct {
            node: ir.Node,
            score: f32,
        };
        var scored_nodes = try std.ArrayList(ScoredNode).initCapacity(self.allocator, nodes.len);
        defer scored_nodes.deinit(self.allocator);

        for (nodes) |node| {
            const score = self.calculateImportanceScore(node, nodes, edges);
            try scored_nodes.append(self.allocator, .{ .node = node, .score = score });
        }

        // Sort by score (descending)
        std.mem.sort(ScoredNode, scored_nodes.items, {}, struct {
            fn less(_: void, a: ScoredNode, b: ScoredNode) bool {
                return a.score > b.score;
            }
        }.less);

        // Keep top nodes
        var kept_nodes = try std.ArrayList(ir.Node).initCapacity(self.allocator, 0);
        defer kept_nodes.deinit(self.allocator);

        var kept_node_ids = std.StringHashMap(void).init(self.allocator);
        defer kept_node_ids.deinit();

        for (scored_nodes.items[0..max_nodes]) |scored_node| {
            try kept_nodes.append(self.allocator, scored_node.node);
            try kept_node_ids.put(scored_node.node.id, {});
        }

        // Filter edges
        var kept_edges = try std.ArrayList(ir.Edge).initCapacity(self.allocator, 0);
        defer kept_edges.deinit(self.allocator);

        for (edges) |edge| {
            if (kept_node_ids.contains(edge.src) and kept_node_ids.contains(edge.dst)) {
                try kept_edges.append(self.allocator, edge);
            }
        }

        return .{
            .nodes = try kept_nodes.toOwnedSlice(self.allocator),
            .edges = try kept_edges.toOwnedSlice(self.allocator),
        };
    }

    /// Hybrid pruning combining degree threshold with importance scoring
    fn pruneByHybridDegreeImportance(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge) !PruningResult {
        // First calculate importance scores
        var node_scores = std.StringHashMap(f32).init(self.allocator);
        defer node_scores.deinit();

        for (nodes) |node| {
            const score = self.calculateImportanceScore(node, nodes, edges);
            try node_scores.put(node.id, score);
        }

        // Calculate node degrees
        var node_degrees = std.StringHashMap(u32).init(self.allocator);
        defer node_degrees.deinit();

        // Initialize degrees
        for (nodes) |node| {
            try node_degrees.put(node.id, 0);
        }

        // Count degrees from edges
        for (edges) |edge| {
            if (node_degrees.getPtr(edge.src)) |degree| {
                degree.* += 1;
            }
            if (node_degrees.getPtr(edge.dst)) |degree| {
                degree.* += 1;
            }
        }

        // Filter nodes using hybrid criteria
        var kept_nodes = try std.ArrayList(ir.Node).initCapacity(self.allocator, 0);
        defer kept_nodes.deinit(self.allocator);

        var kept_node_ids = std.StringHashMap(void).init(self.allocator);
        defer kept_node_ids.deinit();

        for (nodes) |node| {
            const degree = node_degrees.get(node.id) orelse 0;
            const importance = node_scores.get(node.id) orelse 0.0;

            // Hybrid criteria: meet degree threshold OR have high importance
            const keep_node = degree >= self.config.min_degree or
                importance >= self.config.min_importance or
                (degree >= 1 and importance >= 0.5); // Compromise for medium nodes

            if (keep_node) {
                try kept_nodes.append(self.allocator, node);
                try kept_node_ids.put(node.id, {});
            }
        }

        // Filter edges
        var kept_edges = try std.ArrayList(ir.Edge).initCapacity(self.allocator, 0);
        defer kept_edges.deinit(self.allocator);

        for (edges) |edge| {
            if (kept_node_ids.contains(edge.src) and kept_node_ids.contains(edge.dst)) {
                try kept_edges.append(self.allocator, edge);
            }
        }

        return PruningResult{
            .nodes = try kept_nodes.toOwnedSlice(self.allocator),
            .edges = try kept_edges.toOwnedSlice(self.allocator),
        };
    }

    /// Language-aware pruning that preserves cross-language edges
    fn pruneByLanguageAware(self: *const PruningEngine, nodes: []const ir.Node, edges: []const ir.Edge) !PruningResult {
        // Identify cross-language edges
        var cross_lang_edges = std.ArrayList(ir.Edge).initCapacity(self.allocator, 20) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer cross_lang_edges.deinit(self.allocator);

        var node_lang_map = std.StringHashMap([]const u8).init(self.allocator);
        defer node_lang_map.deinit();

        // Build node language map
        for (nodes) |node| {
            try node_lang_map.put(node.id, node.lang);
        }

        // Identify cross-language edges
        for (edges) |edge| {
            const src_lang = node_lang_map.get(edge.src) orelse "";
            const dst_lang = node_lang_map.get(edge.dst) orelse "";
            if (!std.mem.eql(u8, src_lang, dst_lang)) {
                try cross_lang_edges.append(self.allocator, edge);
            }
        }

        // Mark nodes involved in cross-language edges as protected
        var protected_nodes = std.StringHashMap(void).init(self.allocator);
        defer protected_nodes.deinit();

        for (cross_lang_edges.items) |edge| {
            try protected_nodes.put(edge.src, {});
            try protected_nodes.put(edge.dst, {});
        }

        // Calculate importance scores with bonus for cross-language nodes
        var node_scores = std.StringHashMap(f32).init(self.allocator);
        defer node_scores.deinit();

        for (nodes) |node| {
            var score = self.calculateImportanceScore(node, nodes, edges);

            // Add bonus for cross-language connectivity
            if (protected_nodes.contains(node.id)) {
                score += 0.3; // 30% bonus for cross-language nodes
            }

            try node_scores.put(node.id, score);
        }

        // Filter nodes based on importance with cross-language preservation
        var kept_nodes = try std.ArrayList(ir.Node).initCapacity(self.allocator, 0);
        defer kept_nodes.deinit(self.allocator);

        var kept_node_ids = std.StringHashMap(void).init(self.allocator);
        defer kept_node_ids.deinit();

        for (nodes) |node| {
            const score = node_scores.get(node.id) orelse 0.0;
            const is_protected = protected_nodes.contains(node.id);

            // Keep if protected or meets importance threshold
            if (is_protected or score >= self.config.min_importance) {
                try kept_nodes.append(self.allocator, node);
                try kept_node_ids.put(node.id, {});
            }
        }

        // Filter edges
        var kept_edges = try std.ArrayList(ir.Edge).initCapacity(self.allocator, 0);
        defer kept_edges.deinit(self.allocator);

        for (edges) |edge| {
            if (kept_node_ids.contains(edge.src) and kept_node_ids.contains(edge.dst)) {
                try kept_edges.append(self.allocator, edge);
            }
        }

        return PruningResult{
            .nodes = try kept_nodes.toOwnedSlice(self.allocator),
            .edges = try kept_edges.toOwnedSlice(self.allocator),
        };
    }
};
