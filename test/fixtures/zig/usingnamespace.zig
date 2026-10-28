const std = @import("std");

// Test file for various Zig patterns that need frontend support

// Function declarations
pub fn simpleFunction() void {
    const x = 42;
    _ = x;
}

// Private function
fn privateFunction() void {}

// Struct declarations
pub const SimpleStruct = struct {
    field: u32,

    pub fn method(self: @This()) void {
        _ = self;
    }
};

// Import statements
const imported_module = @import("std");

// Comptime blocks
comptime {
    const x = 42;
    _ = x;
}

// Test various patterns for the frontend to detect
pub fn testPatterns() void {
    // Function calls
    simpleFunction();
    privateFunction();

    // Struct instantiation
    const s = SimpleStruct{ .field = 42 };

    // Method calls
    s.method();
}
