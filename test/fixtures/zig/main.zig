const std = @import("std");
const auth = @import("auth.zig");
const database = @import("database.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Initialize database connection
    var db = try database.init(allocator);
    defer db.deinit();

    // Authenticate user
    const user = try auth.authenticate("admin", "password");
    std.debug.print("Authenticated user: {s}\n", .{user.name});

    // Run main application logic
    try runApp(&db, user);
}

fn runApp(db: *database.Database, user: auth.User) !void {
    const data = try db.queryUser(user.id);
    std.debug.print("User data: {}\n", .{data});
}
