const std = @import("std");
const ir = @import("ir");

pub fn JsonEmitter(comptime WriterType: type) type {
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

        pub fn emit(self: Self, ir_data: ir.IR) !void {
            try self.writer.interface.writeAll("{\n");
            try self.writer.interface.writeAll("  \"schema_version\": ");
            try self.writer.interface.print("{d}", .{ir_data.schema_version});
            try self.writer.interface.writeAll(",\n");

            try self.writer.interface.writeAll("  \"graph\": ");
            try self.emitGraph(ir_data.graph);
            try self.writer.interface.writeAll(",\n");

            try self.writer.interface.writeAll("  \"manifest\": ");
            try self.emitManifest(ir_data.manifest);
            try self.writer.interface.writeAll(",\n");

            try self.writer.interface.writeAll("  \"diagnostics\": ");
            try self.emitDiagnostics(ir_data.diagnostics);
            try self.writer.interface.writeAll("\n");

            try self.writer.interface.writeAll("}\n");
        }

        fn emitGraph(self: Self, graph: ir.Graph) !void {
            try self.writer.interface.writeAll("{\n");
            try self.writer.interface.writeAll("    \"nodes\": ");
            try self.emitNodes(graph.nodes);
            try self.writer.interface.writeAll(",\n");
            try self.writer.interface.writeAll("    \"edges\": ");
            try self.emitEdges(graph.edges);
            try self.writer.interface.writeAll("\n");
            try self.writer.interface.writeAll("  }");
        }

        fn emitNodes(self: Self, nodes: []const ir.Node) !void {
            if (nodes.len == 0) {
                try self.writer.interface.writeAll("[]");
                return;
            }

            try self.writer.interface.writeAll("[\n");
            for (nodes, 0..) |node, i| {
                if (i > 0) try self.writer.interface.writeAll(",\n");
                try self.emitNode(node);
            }
            try self.writer.interface.writeAll("\n    ]");
        }

        fn emitNode(self: Self, node: ir.Node) !void {
            try self.writer.interface.writeAll("      {\n");
            try self.emitStringField("id", node.id);
            try self.emitStringField("lang", node.lang);
            try self.emitStringField("kind", @tagName(node.kind));
            try self.emitStringField("name", node.name);
            try self.emitStringField("fqname", node.fqname);
            try self.emitStringField("file", node.file);

            try self.writer.interface.writeAll("        \"range\": ");
            try self.emitRange(node.range);
            try self.writer.interface.writeAll(",\n");

            if (node.signature) |signature| {
                try self.emitStringField("signature", signature);
            }

            try self.emitStringField("visibility", @tagName(node.visibility));
            try self.emitStringFieldNoComma("origin_plugin", node.origin_plugin);

            if (node.module_id) |module_id| {
                try self.writer.interface.writeAll(",\n");
                try self.emitStringFieldNoComma("module_id", module_id);
            }

            try self.writer.interface.writeAll(",\n        \"tags\": [");
            for (node.tags, 0..) |tag, j| {
                if (j > 0) try self.writer.interface.writeAll(", ");
                try self.writeString(tag);
            }
            try self.writer.interface.writeAll("]\n");

            try self.writer.interface.writeAll("      }");
        }

        fn emitRange(self: Self, range: ir.Range) !void {
            try self.writer.interface.writeAll("{\n");
            try self.writer.interface.print("          \"l0\": {d},\n", .{range.start.line});
            try self.writer.interface.print("          \"c0\": {d},\n", .{range.start.column});
            try self.writer.interface.print("          \"l1\": {d},\n", .{range.end.line});
            try self.writer.interface.print("          \"c1\": {d}\n", .{range.end.column});
            try self.writer.interface.writeAll("        }");
        }

        fn emitEdges(self: Self, edges: []const ir.Edge) !void {
            if (edges.len == 0) {
                try self.writer.interface.writeAll("[]");
                return;
            }

            try self.writer.interface.writeAll("[\n");
            for (edges, 0..) |edge, i| {
                if (i > 0) try self.writer.interface.writeAll(",\n");
                try self.emitEdge(edge);
            }
            try self.writer.interface.writeAll("\n    ]");
        }

        fn emitEdge(self: Self, edge: ir.Edge) !void {
            try self.writer.interface.writeAll("      {\n");
            try self.emitStringField("src", edge.src);
            try self.emitStringField("dst", edge.dst);
            try self.emitStringField("rel", @tagName(edge.rel));
            try self.emitStringField("certainty", @tagName(edge.certainty));
            try self.writer.interface.writeAll("        \"evidence_paths\": [");
            for (edge.evidence_paths, 0..) |path, j| {
                if (j > 0) try self.writer.interface.writeAll(", ");
                try self.writeString(path);
            }
            try self.writer.interface.writeAll("],\n        \"evidence_lines\": [");
            for (edge.evidence_lines, 0..) |line, j| {
                if (j > 0) try self.writer.interface.writeAll(", ");
                try self.writer.interface.print("{d}", .{line});
            }
            try self.writer.interface.writeAll("]\n      }");
        }

        fn emitManifest(self: Self, manifest: ir.GraphManifest) !void {
            try self.writer.interface.writeAll("{\n");
            try self.writer.interface.writeAll("    \"generated_at\": ");
            try self.writeString(manifest.generated_at);
            try self.writer.interface.writeAll(",\n");
            try self.writer.interface.writeAll("    \"generator_version\": ");
            try self.writeString(manifest.generator_version);
            try self.writer.interface.writeAll(",\n");
            try self.writer.interface.writeAll("    \"graph_type\": ");
            try self.writeString(manifest.graph_type);
            try self.writer.interface.writeAll(",\n");
            try self.writer.interface.writeAll("    \"input_root\": ");
            try self.writeString(manifest.input_root);
            try self.writer.interface.writeAll(",\n");
            try self.writer.interface.print("    \"schema_version\": {d},\n", .{manifest.schema_version});
            try self.writer.interface.print("    \"node_count\": {d},\n", .{manifest.node_count});
            try self.writer.interface.print("    \"edge_count\": {d},\n", .{manifest.edge_count});
            try self.writer.interface.print("    \"resolved_refs\": {d},\n", .{manifest.resolved_refs});
            try self.writer.interface.print("    \"unresolved_refs\": {d},\n", .{manifest.unresolved_refs});
            try self.writer.interface.print("    \"resolution_rate\": {d:.1},\n", .{manifest.resolution_rate});
            try self.writer.interface.print("    \"cache_hits\": {d},\n", .{manifest.cache_hits});
            try self.writer.interface.print("    \"cache_misses\": {d},\n", .{manifest.cache_misses});
            try self.writer.interface.writeAll("    \"plugins_used\": ");
            try self.emitPluginSummaries(manifest.plugins_used);
            try self.writer.interface.writeAll(",\n    \"cli_args\": ");
            if (manifest.cli_args.len > 0) {
                try self.writer.interface.writeAll("[");
                for (manifest.cli_args, 0..) |arg, j| {
                    if (j > 0) try self.writer.interface.writeAll(", ");
                    try self.writeString(arg);
                }
                try self.writer.interface.writeAll("]\n");
            } else {
                try self.writer.interface.writeAll("[]\n");
            }
            try self.writer.interface.writeAll("  }");
        }

        fn emitPluginSummaries(self: Self, plugins: []const ir.PluginSummary) !void {
            if (plugins.len == 0) {
                try self.writer.interface.writeAll("[]");
                return;
            }
            try self.writer.interface.writeAll("[\n");
            for (plugins, 0..) |plugin, i| {
                if (i > 0) try self.writer.interface.writeAll(",\n");
                try self.writer.interface.writeAll("          {\n");
                try self.emitStringField("id", plugin.id);
                try self.emitStringField("version", plugin.version);
                try self.writer.interface.print("          \"schema_min\": {d},\n", .{plugin.schema_min});
                try self.writer.interface.print("          \"schema_max\": {d}\n", .{plugin.schema_max});
                try self.writer.interface.writeAll("          }");
            }
            try self.writer.interface.writeAll("\n        ]");
        }

        fn emitDiagnostics(self: Self, diagnostics: []const ir.FullDiagnostic) !void {
            if (diagnostics.len == 0) {
                try self.writer.interface.writeAll("[\n  ]");
                return;
            }
            try self.writer.interface.writeAll("[\n");
            for (diagnostics, 0..) |diag, i| {
                if (i > 0) try self.writer.interface.writeAll(",\n");
                try self.emitDiagnostic(diag);
            }
            try self.writer.interface.writeAll("\n  ]");
        }

        fn emitDiagnostic(self: Self, diag: ir.FullDiagnostic) !void {
            try self.writer.interface.writeAll("    {\n");
            try self.emitStringField("id", diag.id);
            try self.emitStringField("severity", diag.severity.toString());
            try self.emitStringField("code", diag.code);

            if (diag.file) |file| {
                try self.emitStringField("file", file);
            }

            if (diag.range) |range| {
                try self.writer.interface.writeAll("      \"range\": ");
                try self.emitRange(range);
                try self.writer.interface.writeAll(",\n");
            }

            if (diag.plugin) |plugin| {
                try self.emitStringField("plugin", plugin);
            }

            try self.emitStringFieldNoComma("message", diag.message);
            try self.writer.interface.writeAll("\n    }");
        }

        fn emitStringField(self: Self, name: []const u8, value: []const u8) !void {
            try self.emitStringFieldNoComma(name, value);
            try self.writer.interface.writeAll(",\n");
        }

        fn emitStringFieldNoComma(self: Self, name: []const u8, value: []const u8) !void {
            try self.writer.interface.print("        \"{s}\": ", .{name});
            try self.writeString(value);
        }

        fn writeString(self: Self, value: []const u8) !void {
            try std.json.Stringify.encodeJsonString(value, .{}, &self.writer.interface);
        }
    };
}
