// Synthetic repo fixture used by CLI validation tests.
const std = @import("std");
const auth = @import("auth.zig");
const database = @import("database.zig");

pub fn main() !void {
    const user = auth.User.init("admin", "password123");
    const db = try database.Database.connect("localhost:5432");

    std.debug.print("User: {s}, DB: {s}\n", .{ user.name, db.url });
}
