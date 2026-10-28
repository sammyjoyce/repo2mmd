const std = @import("std");

// Advanced comptime patterns
pub const PUBLIC_COMPTIME = "hello";

comptime {
    // Comptime block with multiple declarations
    const COMPTIME_CONST = 42;

    // Comptime function calls
    const size = @sizeOf(u32);
    const align_val = @alignOf(u32);

    _ = size;
    _ = align_val;
}

// Generic function with comptime parameters
pub fn GenericContainer(comptime T: type, comptime N: usize) type {
    return struct {
        items: [N]T,
        count: usize,

        pub fn init() @This() {
            return .{
                .items = std.mem.zeroes([N]T),
                .count = 0,
            };
        }

        pub fn push(self: *@This(), item: T) !void {
            if (self.count >= N) return error.Overflow;
            self.items[self.count] = item;
            self.count += 1;
        }

        // Comptime method
        pub fn capacity() usize {
            return N;
        }
    };
}

// Comptime introspection functions
pub fn getTypeInfo(comptime T: type) @typeInfo(T) {
    return @typeInfo(T);
}

pub fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    return @hasField(T, field_name);
}

pub fn fieldCount(comptime T: type) usize {
    return std.meta.fields(T).len;
}

// Usage examples
pub const IntContainer = GenericContainer(u32, 10);
pub const StringContainer = GenericContainer([]const u8, 5);

// Comptime assertions
comptime {
    std.debug.assert(@sizeOf(u32) == 4);
    std.debug.assert(@alignOf(u64) == 8);
}

// Conditional compilation
pub fn conditionalFunction() void {
    // This will only be compiled in debug mode
    if (std.debug.runtime_safety) {
        std.debug.print("Debug mode\n");
    }
}

// Built-in comptime functions
pub fn builtinExamples() void {
    const int_type: type = u32;
    const type_info = @typeInfo(int_type);
    const fields = std.meta.fields(IntContainer);

    _ = type_info;
    _ = fields;
}
