const std = @import("std");

// Simple function declarations
pub fn add(a: u32, b: u32) u32 {
    return a + b;
}

pub fn multiply(a: u32, b: u32) u32 {
    return a * b;
}

pub fn divide(a: f32, b: f32) !f32 {
    if (b == 0.0) return error.DivisionByZero;
    return a / b;
}

// Function with multiple calls
pub fn calculate(x: u32, y: u32) struct { sum: u32, product: u32, ratio: ?f32 } {
    const sum = add(x, y);
    const product = multiply(x, y);
    const ratio = divide(@as(f32, @floatFromInt(x)), @as(f32, @floatFromInt(y))) catch null;

    return .{
        .sum = sum,
        .product = product,
        .ratio = ratio,
    };
}

// Recursive function
pub fn factorial(n: u32) u64 {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

// Function pointers
pub const MathOp = *const fn (a: u32, b: u32) u32;

pub fn applyOperation(a: u32, b: u32, op: MathOp) u32 {
    return op(a, b);
}

pub fn getOperation(comptime op_name: []const u8) MathOp {
    if (std.mem.eql(u8, op_name, "add")) {
        return add;
    } else if (std.mem.eql(u8, op_name, "multiply")) {
        return multiply;
    } else {
        @compileError("Unknown operation: " ++ op_name);
    }
}

// Higher-order functions
pub fn map(comptime T: type, comptime U: type, items: []const T, mapper: *const fn (T) U) []U {
    const allocator = std.heap.page_allocator;
    var result = allocator.alloc(U, items.len) catch @panic("OOM");

    for (items, 0..) |item, i| {
        result[i] = mapper(item);
    }

    return result;
}

pub fn filter(comptime T: type, items: []const T, predicate: *const fn (T) bool) []T {
    const allocator = std.heap.page_allocator;
    var temp_list = std.ArrayList(T).init(allocator);
    defer temp_list.deinit();

    for (items) |item| {
        if (predicate(item)) {
            temp_list.append(item) catch @panic("OOM");
        }
    }

    return temp_list.toOwnedSlice() catch @panic("OOM");
}

// Function with closure-like behavior (simplified)
pub fn createCounter(comptime start: u32) struct { count: u32 } {
    return struct { count: u32 }{ .count = start };
}

pub fn incrementCounter(counter: *struct { count: u32 }) u32 {
    counter.count += 1;
    return counter.count;
}

// Method calls on structs
pub const Calculator = struct {
    value: f64,

    pub fn init(value: f64) Calculator {
        return Calculator{ .value = value };
    }

    pub fn add(self: *Calculator, operand: f64) void {
        self.value += operand;
    }

    pub fn multiply(self: *Calculator, operand: f64) void {
        self.value *= operand;
    }

    pub fn reset(self: *Calculator) void {
        self.value = 0.0;
    }

    pub fn getResult(self: *const Calculator) f64 {
        return self.value;
    }
};

// Function that uses Calculator methods
pub fn performCalculations() f64 {
    var calc = Calculator.init(10.0);
    calc.add(5.0);
    calc.multiply(2.0);
    calc.reset();
    calc.add(100.0);
    return calc.getResult();
}

// Builtin function calls
pub fn builtinCalls() void {
    const a: u32 = 42;
    const b: u32 = 24;

    // Type information
    const type_info = @typeInfo(u32);
    _ = type_info;

    // Size and alignment
    const size = @sizeOf(u32);
    const alignment = @alignOf(u32);
    _ = size;
    _ = alignment;

    // Type casting
    const float_a: f32 = @floatFromInt(a);
    const int_b: u32 = @intFromFloat(@as(f32, @floatFromInt(b)));
    _ = float_a;
    _ = int_b;

    // Comptime evaluation
    comptime {
        const result = add(a, b);
        std.debug.assert(result == 66);
    }

    // Error handling
    const division_result = divide(@as(f32, @floatFromInt(a)), @as(f32, @floatFromInt(b)));
    _ = division_result catch 0.0;
}

// Function with multiple parameter types
pub fn complexFunction(
    int_param: u32,
    float_param: f64,
    bool_param: bool,
    slice_param: []const u8,
    optional_param: ?[]const u8,
    error_union_param: anyerror!u32,
) struct {
    int_result: u32,
    float_result: f64,
    bool_result: bool,
    slice_len: usize,
    optional_len: usize,
    error_result: u32,
} {
    return .{
        .int_result = int_param * 2,
        .float_result = float_param / 2.0,
        .bool_result = !bool_param,
        .slice_len = slice_param.len,
        .optional_len = optional_param.?.len,
        .error_result = error_union_param catch 0,
    };
}
