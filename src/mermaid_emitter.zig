const std = @import("std");
const ir = @import("ir");

// Re-export types for convenience
const NodeKind = ir.NodeKind;
const EdgeRel = ir.EdgeRel;
const Certainty = ir.Certainty;
const Visibility = ir.Visibility;
const Position = ir.Position;
const Range = ir.Range;
const Node = ir.Node;
const Edge = ir.Edge;
const DiagnosticRef = ir.DiagnosticRef;
const Graph = ir.Graph;

pub fn MermaidFlowchartEmitter(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        writer: *WriterType,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, writer: *WriterType) Self {
            return .{
                .allocator = allocator,
                .writer = writer,
            };
        }

        pub fn emit(self: Self, graph: Graph, title: ?[]const u8) !void {
            try self.writer.interface.writeAll("graph TD\n");

            if (title) |t| {
                try self.writer.interface.print("    %% {s}\n", .{t});
            }

            // Emit nodes
            var declared = std.StringHashMap(void).init(self.allocator);
            defer declared.deinit();
            for (graph.nodes) |node| {
                try self.emitNode(node);
                try declared.put(node.id, {});
            }

            // Edge endpoints with no node (std, build.zig modules, unresolved
            // imports) get a declaration so Mermaid shows a label, not an ID.
            for (graph.edges) |edge| {
                for ([_][]const u8{ edge.src, edge.dst }) |endpoint| {
                    const entry = try declared.getOrPut(endpoint);
                    if (entry.found_existing) continue;
                    const safe_id = try self.makeSafeId(endpoint);
                    defer self.allocator.free(safe_id);
                    const label = if (std.mem.startsWith(u8, endpoint, "file_")) endpoint["file_".len..] else endpoint;
                    try self.writer.interface.print("    {s}[\"", .{safe_id});
                    try self.writeLabel(label);
                    try self.writer.interface.writeAll("\"]\n");
                }
            }

            // Emit edges
            for (graph.edges) |edge| {
                try self.emitEdge(edge);
            }
        }

        fn emitNode(self: Self, node: Node) !void {
            const safe_name = try self.makeSafeId(node.id);
            defer self.allocator.free(safe_name);

            const label = if (node.name.len > 0) node.name else node.fqname;
            try self.writer.interface.print("    {s}[\"", .{safe_name});
            try self.writeLabel(label);
            try self.writer.interface.writeAll("\"]\n");

            // Add styling based on node kind
            const style = switch (node.kind) {
                .Func => "fill:#e1f5fe",
                .Type => "fill:#f3e5f5",
                .Module => "fill:#e8f5e8",
                .File => "fill:#fff3e0",
                .Var => "fill:#fce4ec",
            };

            try self.writer.interface.print("    style {s} {s}\n", .{ safe_name, style });
        }

        fn emitEdge(self: Self, edge: Edge) !void {
            const safe_src = try self.makeSafeId(edge.src);
            defer self.allocator.free(safe_src);

            const safe_dst = try self.makeSafeId(edge.dst);
            defer self.allocator.free(safe_dst);

            const arrow = switch (edge.rel) {
                .Imports => "-->",
                .Includes => "-.->",
                .Calls => "-->",
                .Contains => "---",
                .Extends => "-->",
                .Implements => "-..->",
            };

            const label = if (edge.certainty != .Static)
                try std.fmt.allocPrint(self.allocator, "|{s}|", .{edge.certainty.toString()})
            else
                "";
            defer if (edge.certainty != .Static) self.allocator.free(label);

            try self.writer.interface.print("    {s} {s}{s} {s}\n", .{ safe_src, arrow, label, safe_dst });
        }

        /// Mermaid IDs allow only [A-Za-z0-9_]. Letters and digits pass through,
        /// "_" becomes "__", and any other byte (or a leading digit) becomes
        /// "_XX" hex, so distinct IR IDs never collide.
        fn makeSafeId(self: Self, id: []const u8) ![]u8 {
            var result = try std.ArrayList(u8).initCapacity(self.allocator, id.len + 1);
            defer result.deinit(self.allocator);

            for (id, 0..) |c, i| {
                switch (c) {
                    'a'...'z', 'A'...'Z' => try result.append(self.allocator, c),
                    '0'...'9' => if (i == 0)
                        try result.print(self.allocator, "_{X:0>2}", .{c})
                    else
                        try result.append(self.allocator, c),
                    '_' => try result.appendSlice(self.allocator, "__"),
                    else => try result.print(self.allocator, "_{X:0>2}", .{c}),
                }
            }

            return result.toOwnedSlice(self.allocator);
        }

        fn writeLabel(self: Self, label: []const u8) !void {
            for (label) |c| {
                switch (c) {
                    '"' => try self.writer.interface.writeAll("#quot;"),
                    '\n', '\r' => try self.writer.interface.writeByte(' '),
                    else => try self.writer.interface.writeByte(c),
                }
            }
        }
    };
}

pub const MermaidClassEmitter = struct {
    allocator: std.mem.Allocator,
    writer: *std.io.Writer,

    pub fn init(allocator: std.mem.Allocator, writer: *std.io.Writer) MermaidClassEmitter {
        return MermaidClassEmitter{
            .allocator = allocator,
            .writer = writer,
        };
    }

    pub fn emit(self: MermaidClassEmitter, graph: Graph, title: ?[]const u8) !void {
        try self.writer.writeAll("classDiagram\n");

        if (title) |t| {
            try self.writer.print("    %% {s}\n", .{t});
        }

        // Group nodes by module/file for better organization
        var modules = std.StringHashMap(std.ArrayList(Node)).init(self.allocator);
        defer {
            var it = modules.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            modules.deinit(self.allocator);
        }

        // Group nodes by module
        for (graph.nodes) |node| {
            const module_id = node.module_id orelse "global";
            const entry = try modules.getOrPut(module_id);
            if (!entry.found_existing) {
                entry.value_ptr.* = try std.ArrayList(Node).initCapacity(self.allocator, 0);
            }
            try entry.value_ptr.append(self.allocator, node);
        }

        // Emit classes for each module
        var module_it = modules.iterator();
        while (module_it.next()) |entry| {
            try self.emitModule(entry.key_ptr.*, entry.value_ptr.items);
        }

        // Emit relationships
        for (graph.edges) |edge| {
            try self.emitRelationship(edge);
        }

        try self.writer.writeAll("\n");
    }

    fn emitModule(self: MermaidClassEmitter, module_id: []const u8, nodes: []const Node) !void {
        _ = module_id;
        for (nodes) |node| {
            switch (node.kind) {
                .Type => try self.emitTypeClass(node),
                .Func => try self.emitFunctionClass(node),
                else => {}, // Skip other node kinds for class diagrams
            }
        }
    }

    fn emitTypeClass(self: MermaidClassEmitter, node: Node) !void {
        const safe_name = try self.makeSafeId(node.id);
        defer self.allocator.free(safe_name);

        try self.writer.print("    class {s} {{\n", .{safe_name});
        try self.writer.print("        <<{s}>>\n", .{node.kind.toString()});

        if (node.signature) |signature| {
            try self.writer.print("        {s}\n", .{signature});
        }

        try self.writer.writeAll("    }\n");
    }

    fn emitFunctionClass(self: MermaidClassEmitter, node: Node) !void {
        const safe_name = try self.makeSafeId(node.id);
        defer self.allocator.free(safe_name);

        try self.writer.print("    class {s} {{\n", .{safe_name});
        try self.writer.print("        <<{s}>>\n", .{node.kind.toString()});

        if (node.signature) |signature| {
            try self.writer.print("        {s}\n", .{signature});
        }

        try self.writer.writeAll("    }\n");
    }

    fn emitRelationship(self: MermaidClassEmitter, edge: Edge) !void {
        const safe_src = try self.makeSafeId(edge.src);
        defer self.allocator.free(safe_src);

        const safe_dst = try self.makeSafeId(edge.dst);
        defer self.allocator.free(safe_dst);

        const relationship = switch (edge.rel) {
            .Extends => "--|>",
            .Implements => "..|>",
            .Contains => "*--",
            .Calls => "-->",
            .Imports => "..>",
            else => "-->",
        };

        const label = if (edge.certainty != .Static)
            try std.fmt.allocPrint(self.allocator, " : {s}", .{edge.certainty.toString()})
        else
            "";
        defer if (edge.certainty != .Static) self.allocator.free(label);

        try self.writer.print("    {s} {s}{s} {s}\n", .{ safe_src, relationship, label, safe_dst });
    }

    fn makeSafeId(self: MermaidClassEmitter, id: []const u8) ![]u8 {
        // Similar to flowchart but with different rules for class diagrams
        var result = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer result.deinit(self.allocator);

        if (id.len > 0 and std.ascii.isDigit(id[0])) {
            try result.append(self.allocator, 'C');
        }

        for (id) |c| {
            switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_' => try result.append(self.allocator, c),
                '-', '.', ':' => try result.append(self.allocator, '_'),
                else => {}, // Skip other characters
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};
