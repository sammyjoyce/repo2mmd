const std = @import("std");

// Comptime function examples
fn add(a: comptime_int, b: comptime_int) comptime_int {
    return a + b;
}

// Comptime block
comptime {
    const x = 5;
    const y = 10;
    const result = add(x, y);
    _ = result; // Use the result
}

// Generic function with comptime parameters
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

// Generic struct with comptime parameters
pub fn Vector(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        pub fn init(x: T, y: T) @This() {
            return @This(){ .x = x, .y = y };
        }

        pub fn magnitude(self: @This()) T {
            return @sqrt(self.x * self.x + self.y * self.y);
        }
    };
}

// Comptime assertions
comptime {
    std.debug.assert(add(2, 3) == 5);
    std.debug.assert(max(u32, 10, 20) == 20);
}

// Simple struct for testing
const TestStruct = struct {
    pub const name = "test";
    pub const version = 1;
};

// Builtin comptime functions
pub fn getTypeInfo(comptime T: type) std.builtin.TypeInfo {
    return @typeInfo(T);
}

pub fn sizeOf(comptime T: type) usize {
    return @sizeOf(T);
}

pub fn alignOf(comptime T: type) usize {
    return @alignOf(T);
}

// Comptime enum
pub const Color = enum {
    red,
    green,
    blue,

    pub fn rgbValue(self: Color) u32 {
        return switch (self) {
            .red => 0xFF0000,
            .green => 0x00FF00,
            .blue => 0x0000FF,
        };
    }
};
