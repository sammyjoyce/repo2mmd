const std = @import("std");

// Error union types
pub const ParseError = error{
    InvalidSyntax,
    UnexpectedToken,
    EndOfStream,
};

pub const ParseResult = union(ParseError) {
    success: u32,
    failure: ParseError,
};

// Generic types with constraints
pub fn Container(comptime T: type, comptime size: usize) type {
    return struct {
        items: [size]T,
        count: usize,

        pub fn init() @This() {
            return .{
                .items = std.mem.zeroes([size]T),
                .count = 0,
            };
        }

        pub fn add(self: *@This(), item: T) !void {
            if (self.count >= size) return error.Overflow;
            self.items[self.count] = item;
            self.count += 1;
        }
    };
}

// Function pointers and callbacks
pub const Callback = *const fn (data: []const u8) void;

pub fn processData(data: []const u8, callback: Callback) void {
    callback(data);
}

// Tagged unions
pub const Value = union(enum) {
    integer: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    null: void,

    pub fn format(self: Value, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .integer => |v| std.fmt.allocPrint(allocator, "{}", .{v}),
            .float => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
            .string => |v| std.fmt.allocPrint(allocator, "\"{s}\"", .{v}),
            .boolean => |v| std.fmt.allocPrint(allocator, "{}", .{v}),
            .null => std.fmt.allocPrint(allocator, "null", .{}),
        };
    }
};

// Comptime introspection
pub fn getFieldNames(comptime T: type) []const []const u8 {
    return std.meta.fieldNames(T);
}

pub fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    return @hasField(T, field_name);
}

// Async functions (simplified)
pub const AsyncResult = struct {
    value: u32,
    completed: bool,
};

pub fn asyncOperation(comptime delay_ms: u32) AsyncResult {
    _ = delay_ms; // In real async, would wait here
    return AsyncResult{
        .value = 42,
        .completed = true,
    };
}

// Package-level variables
var global_counter: u32 = 0;

pub fn incrementGlobal() u32 {
    global_counter += 1;
    return global_counter;
}

// Threadlocal storage
threadlocal var thread_counter: u32 = 0;

pub fn incrementThread() u32 {
    thread_counter += 1;
    return thread_counter;
}

// Defer and errdefer
pub fn withDefer() !void {
    const file = std.fs.cwd().openFile("test.txt", .{}) catch |err| switch (err) {
        error.FileNotFound => return error.MissingFile,
        else => return err,
    };
    defer file.close();

    var buffer: [100]u8 = undefined;
    _ = try file.readAll(&buffer);
}

pub fn withErrdefer() !void {
    const allocator = std.heap.page_allocator;

    const data = try allocator.alloc(u8, 1000);
    errdefer allocator.free(data);

    // Some operation that might fail
    if (data.len == 0) return error.EmptyData;

    allocator.free(data);
}

// Built-in functions usage
pub fn builtinExamples() void {
    const int_type: type = u32;
    const align_val = @alignOf(int_type);
    const size_val = @sizeOf(int_type);
    const type_info = @typeInfo(int_type);

    _ = align_val;
    _ = size_val;
    _ = type_info;

    // Type casting
    const float_val: f32 = 3.14;
    const int_val: i32 = @intFromFloat(float_val);
    _ = int_val;

    // Compile-time checks
    comptime {
        std.debug.assert(@alignOf(u32) == 4);
        std.debug.assert(@sizeOf(u64) == 8);
    }
}
