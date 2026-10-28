const std = @import("std");

pub const Config = struct {
    graph_type: []const u8,
};

pub const Lifecycle = struct {
    context: *anyopaque,
    init_fn: *const fn (*anyopaque) anyerror!void,
    parse_fn: *const fn (*anyopaque) anyerror!void,
    render_fn: *const fn (*anyopaque) anyerror!void,
    reset_fn: *const fn (*anyopaque) void,
};

pub const Entry = struct {
    name: []const u8,
    detector: *const fn (*anyopaque, Config) bool,
    detector_ctx: *anyopaque,
    builder: *const fn (*anyopaque, Config) anyerror!Lifecycle,
    builder_ctx: *anyopaque,
    precedence: u32,
    opt_out: bool = false,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.array_list.Managed(Entry),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .entries = std.array_list.Managed(Entry).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        self.entries.deinit();
    }

    pub fn register(self: *Registry, entry: Entry) !void {
        var insert_index: usize = 0;
        while (insert_index < self.entries.items.len and self.entries.items[insert_index].precedence >= entry.precedence) : (insert_index += 1) {}
        try self.entries.insert(insert_index, entry);
    }

    pub fn select(self: *Registry, config: Config) anyerror!Lifecycle {
        for (self.entries.items) |entry| {
            if (entry.detector(entry.detector_ctx, config)) {
                return entry.builder(entry.builder_ctx, config);
            }
        }
        return error.NotFound;
    }
};
