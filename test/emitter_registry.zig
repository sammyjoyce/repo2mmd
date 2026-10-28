const std = @import("std");
const registry_mod = @import("emitter_registry");

const Config = registry_mod.Config;
const Registry = registry_mod.Registry;
const Entry = registry_mod.Entry;
const Lifecycle = registry_mod.Lifecycle;

const StageState = struct {
    events: [16][]const u8 = undefined,
    count: usize = 0,
    resets: u32 = 0,

    fn push(self: *StageState, label: []const u8) void {
        if (self.count >= self.events.len) return;
        self.events[self.count] = label;
        self.count += 1;
    }
};

pub fn run(allocator: std.mem.Allocator) !void {
    try testDetectorPrecedence(allocator);
    try testOptOutAndFallback(allocator);
    try testLifecycleOrderingAndReset(allocator);
}

fn makeEntry(
    name: []const u8,
    state: *DetectorState,
    precedence: u32,
    lifecycle: *StageState,
) Entry {
    return .{
        .name = name,
        .detector = struct {
            fn detect(ctx: *anyopaque, config: Config) bool {
                const st = @as(*DetectorState, @ptrCast(@alignCast(ctx)));
                st.calls += 1;
                var matched = false;
                for (st.matches) |pattern| {
                    if (pattern.len == 1 and pattern[0] == '*') {
                        matched = true;
                        break;
                    }
                    if (std.mem.eql(u8, config.graph_type, pattern)) {
                        matched = true;
                        break;
                    }
                }
                if (!matched and st.opt_out) {
                    st.opt_out_hits += 1;
                }
                return matched;
            }
        }.detect,
        .detector_ctx = state,
        .builder = struct {
            fn build(ctx: *anyopaque, _: Config) anyerror!Lifecycle {
                _ = @as(*StageState, @ptrCast(@alignCast(ctx)));
                return Lifecycle{
                    .context = ctx,
                    .init_fn = struct {
                        fn call(inner_ctx: *anyopaque) anyerror!void {
                            const ls = @as(*StageState, @ptrCast(@alignCast(inner_ctx)));
                            ls.push("init");
                            return;
                        }
                    }.call,
                    .parse_fn = struct {
                        fn call(inner_ctx: *anyopaque) anyerror!void {
                            const ls = @as(*StageState, @ptrCast(@alignCast(inner_ctx)));
                            ls.push("parse");
                            return;
                        }
                    }.call,
                    .render_fn = struct {
                        fn call(inner_ctx: *anyopaque) anyerror!void {
                            const ls = @as(*StageState, @ptrCast(@alignCast(inner_ctx)));
                            ls.push("render");
                            return;
                        }
                    }.call,
                    .reset_fn = struct {
                        fn call(inner_ctx: *anyopaque) void {
                            const ls = @as(*StageState, @ptrCast(@alignCast(inner_ctx)));
                            ls.resets += 1;
                            ls.count = 0;
                        }
                    }.call,
                };
            }
        }.build,
        .builder_ctx = lifecycle,
        .precedence = precedence,
        .opt_out = state.opt_out,
    };
}

const DetectorState = struct {
    name: []const u8,
    calls: u32 = 0,
    matches: []const []const u8,
    opt_out: bool = false,
    opt_out_hits: u32 = 0,
};

fn testDetectorPrecedence(allocator: std.mem.Allocator) !void {
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var flow_state = DetectorState{ .name = "flow", .matches = &.{"flow"} };
    var class_state = DetectorState{ .name = "class", .matches = &.{"class"} };
    var fallback_state = DetectorState{ .name = "fallback", .matches = &.{"*"} };

    var flow_lifecycle = StageState{};
    var class_lifecycle = StageState{};
    var fallback_lifecycle = StageState{};

    try registry.register(makeEntry("flow", &flow_state, 100, &flow_lifecycle));
    try registry.register(makeEntry("class", &class_state, 50, &class_lifecycle));
    try registry.register(makeEntry("fallback", &fallback_state, 0, &fallback_lifecycle));

    const pipeline = try registry.select(.{ .graph_type = "flow" });
    try pipeline.init_fn(pipeline.context);
    try pipeline.parse_fn(pipeline.context);
    try pipeline.render_fn(pipeline.context);

    try std.testing.expectEqual(@as(u32, 1), flow_state.calls);
    try std.testing.expectEqual(@as(u32, 0), class_state.calls);
    try std.testing.expectEqual(@as(u32, 0), fallback_state.calls);
}

fn testOptOutAndFallback(allocator: std.mem.Allocator) !void {
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var non_matching = DetectorState{ .name = "flow", .matches = &.{}, .opt_out = true };
    var fallback = DetectorState{ .name = "fallback", .matches = &.{"*"} };

    var non_matching_lifecycle = StageState{};
    var fallback_lifecycle = StageState{};

    try registry.register(makeEntry("flow", &non_matching, 10, &non_matching_lifecycle));
    try registry.register(makeEntry("fallback", &fallback, 0, &fallback_lifecycle));

    const pipeline = try registry.select(.{ .graph_type = "unknown" });
    try pipeline.init_fn(pipeline.context);
    try pipeline.parse_fn(pipeline.context);
    try pipeline.render_fn(pipeline.context);
    pipeline.reset_fn(pipeline.context);

    try std.testing.expectEqual(@as(u32, 1), non_matching.calls);
    try std.testing.expectEqual(@as(u32, 1), non_matching.opt_out_hits);
    try std.testing.expectEqual(@as(u32, 1), fallback.calls);
    try std.testing.expectEqual(@as(u32, 1), fallback_lifecycle.resets);
}

fn testLifecycleOrderingAndReset(allocator: std.mem.Allocator) !void {
    var registry = Registry.init(allocator);
    defer registry.deinit();

    var state = DetectorState{ .name = "flow", .matches = &.{"flow"} };
    var lifecycle = StageState{};

    try registry.register(makeEntry("flow", &state, 10, &lifecycle));

    const pipeline = try registry.select(.{ .graph_type = "flow" });
    try pipeline.init_fn(pipeline.context);
    try pipeline.parse_fn(pipeline.context);
    try pipeline.render_fn(pipeline.context);
    pipeline.reset_fn(pipeline.context);

    try std.testing.expectEqual(@as(usize, 0), lifecycle.count);
    try std.testing.expectEqual(@as(u32, 1), lifecycle.resets);
}
