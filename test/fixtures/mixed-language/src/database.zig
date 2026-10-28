const std = @import("std");
const c = @cImport(@cInclude("../include/database.h"));

pub const Database = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    connection: ?*c.database_connection_t,

    pub fn init(connection_string: []const u8) !Self {
        const conn = c.database_connect(connection_string.ptr) orelse return error.ConnectionFailed;

        return Self{
            .allocator = std.heap.page_allocator,
            .connection = conn,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.connection) |conn| {
            c.database_close(conn);
        }
    }

    pub fn loadUser(self: *Self, user_id: u32) !User {
        if (self.connection) |conn| {
            const c_user = c.database_load_user(conn, user_id) orelse return error.UserNotFound;
            defer c.database_free_user(c_user);

            const name = try self.allocator.dupe(u8, std.mem.span(c_user.name));
            const email = try self.allocator.dupe(u8, std.mem.span(c_user.email));

            return User{
                .id = user_id,
                .name = name,
                .email = email,
            };
        }

        return error.NotConnected;
    }

    pub fn saveUser(self: *Self, user: User) !void {
        if (self.connection) |conn| {
            const c_name = try self.allocator.dupeZ(u8, user.name);
            defer self.allocator.free(c_name);

            const c_email = try self.allocator.dupeZ(u8, user.email);
            defer self.allocator.free(c_email);

            const success = c.database_save_user(conn, user.id, c_name, c_email);
            if (!success) return error.SaveFailed;
        }
    }
};

pub const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,

    pub fn deinit(self: *User, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.email);
    }
};
