const std = @import("std");
const ir = @import("ir");

test "ir manifest serializes with escaped strings" {
    const allocator = std.testing.allocator;

    const manifest = ir.Manifest{
        .root = "C:\\repo\"test\x08",
        .input_root = "line\ncol\t",
    };

    const actual = try manifest.serialize(allocator);
    defer allocator.free(actual);

    const expected = "{\"version\":\"1.0.0\",\"root\":\"C\\\\repo\\\"test\\b\",\"graph_type\":\"Deps\",\"input_root\":\"line\\ncol\\t\",\"node_count\":0,\"edge_count\":0,\"unresolved_refs\":0,\"cache_stats\":{\"hits\":0,\"misses\":0},\"plugins_used\":[],\"nodes\":[],\"edges\":[],\"diagnostics\":[]}\n";

    try std.testing.expectEqualStrings(expected, actual);
}

test "ir manifest serializes deterministic ordering" {
    const allocator = std.testing.allocator;

    const plugins = [_]ir.Plugin{
        .{ .id = "zig", .version = "0", .language = "zig" },
        .{ .id = "c", .version = "0", .language = "c" },
    };

    const nodes = [_]ir.Node{
        .{ .id = "b" },
        .{ .id = "a" },
    };

    const edges = [_]ir.Edge{
        .{ .src = "n2", .dst = "n3", .rel = "calls" },
        .{ .src = "n1", .dst = "n2", .rel = "imports" },
    };

    const manifest = ir.Manifest{
        .root = "/abs",
        .input_root = "/abs",
        .plugins_used = &plugins,
        .nodes = &nodes,
        .edges = &edges,
    };

    const actual = try manifest.serialize(allocator);
    defer allocator.free(actual);

    const expected = "{\"version\":\"1.0.0\",\"root\":\"/abs\",\"graph_type\":\"Deps\",\"input_root\":\"/abs\",\"node_count\":0,\"edge_count\":0,\"unresolved_refs\":0,\"cache_stats\":{\"hits\":0,\"misses\":0},\"plugins_used\":[{\"id\":\"zig\",\"version\":\"0\",\"language\":\"zig\"},{\"id\":\"c\",\"version\":\"0\",\"language\":\"c\"}],\"nodes\":[{\"id\":\"b\"},{\"id\":\"a\"}],\"edges\":[{\"src\":\"n2\",\"dst\":\"n3\",\"rel\":\"calls\"},{\"src\":\"n1\",\"dst\":\"n2\",\"rel\":\"imports\"}],\"diagnostics\":[]}\n";

    try std.testing.expectEqualStrings(expected, actual);
}
