const std = @import("std");
const c = @cImport(@cInclude("../include/auth.h"));

// Import our own modules
const auth = @import("auth.zig");
const database = @import("database.zig");

pub fn main() !void {
    // Initialize authentication
    const auth_service = try auth.AuthService.init();
    defer auth_service.deinit();

    // Initialize database
    const db = try database.Database.init("sqlite://app.db");
    defer db.deinit();

    // Use C library functions
    const user_id = c.authenticate_user("admin", "password");
    if (user_id > 0) {
        std.debug.print("User authenticated: {d}\n", .{user_id});

        // Load user data
        const user = try db.loadUser(user_id);
        defer user.deinit();

        std.debug.print("User: {s}\n", .{user.name});
    }

    // Start web service
    try startWebService(auth_service, db);
}

fn startWebService(auth_service: auth.AuthService, db: database.Database) !void {
    const server = std.http.Server.init(std.heap.page_allocator);
    defer server.deinit();

    const addr = try std.net.Address.parseIp("127.0.0.1", 8080);
    try server.listen(addr);

    std.debug.print("Server listening on 8080\n");

    while (true) {
        const connection = server.accept() catch continue;
        defer connection.stream.close();

        handleRequest(connection, auth_service, db) catch |err| {
            std.debug.print("Request error: {}\n", .{err});
        };
    }
}

fn handleRequest(connection: std.net.Server.Connection, auth_service: auth.AuthService, db: database.Database) !void {
    _ = connection;
    _ = auth_service;
    _ = db;
    // TODO: Implement HTTP request handling
}
