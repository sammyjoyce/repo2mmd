const std = @import("std");
const ir = @import("../src/ir.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create test nodes like the Zig plugin creates
    var nodes = try allocator.alloc(ir.Node, 3);
    defer allocator.free(nodes);

    // File nodes
    nodes[0] = ir.Node{
        .id = "file_main.zig",
        .lang = "zig",
        .kind = .File,
        .name = "main.zig",
        .fqname = "main.zig",
        .file = "main.zig",
        .visibility = .Public,
        .origin_plugin = "zig",
    };

    nodes[1] = ir.Node{
        .id = "file_auth.zig",
        .lang = "zig",
        .kind = .File,
        .name = "auth.zig",
        .fqname = "auth.zig",
        .file = "auth.zig",
        .visibility = .Public,
        .origin_plugin = "zig",
    };

    nodes[2] = ir.Node{
        .id = "file_database.zig",
        .lang = "zig",
        .kind = .File,
        .name = "database.zig",
        .fqname = "database.zig",
        .file = "database.zig",
        .visibility = .Public,
        .origin_plugin = "zig",
    };

    // Create test edges like the Zig plugin creates
    var edges = try allocator.alloc(ir.Edge, 2);
    defer allocator.free(edges);

    edges[0] = ir.Edge{
        .src = "file_main.zig",
        .dst = "file_auth.zig",
        .rel = .Imports,
        .certainty = .Static,
    };

    edges[1] = ir.Edge{
        .src = "file_main.zig",
        .dst = "file_database.zig",
        .rel = .Imports,
        .certainty = .Static,
    };

    // Test resolution
    const Resolver = @import("../src/resolver.zig").Resolver;
    const ResolverConfig = @import("../src/resolver.zig").ResolverConfig;

    var resolver = try Resolver.init(allocator, ResolverConfig{});
    defer resolver.deinit();

    try resolver.buildSymbolTables(nodes);

    const resolved_edges = try resolver.resolveEdges(nodes, edges);
    defer allocator.free(resolved_edges);

    const stats = resolver.getStats();
    std.debug.print("Resolution stats: {d}/{d} resolved ({d:.1}%)\n", .{
        stats.resolved_refs,
        stats.resolved_refs + stats.unresolved_refs,
        stats.resolution_rate,
    });

    for (resolved_edges, 0..) |edge, i| {
        std.debug.print("Edge {d}: {s} -> {s}\n", .{ i, edge.src, edge.dst });
    }
}
