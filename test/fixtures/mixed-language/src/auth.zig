const std = @import("std");
const c = @cImport(@cInclude("../include/auth.h"));

pub const AuthService = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    sessions: std.StringHashMap(u32),

    pub fn init() !Self {
        return Self{
            .allocator = std.heap.page_allocator,
            .sessions = std.StringHashMap(u32).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.sessions.deinit();
    }

    pub fn authenticate(self: *Self, username: []const u8, password: []const u8) !u32 {
        // Use C library for authentication
        const c_username = try self.allocator.dupeZ(u8, username);
        defer self.allocator.free(c_username);

        const c_password = try self.allocator.dupeZ(u8, password);
        defer self.allocator.free(c_password);

        const user_id = c.authenticate_user(c_username, c_password);

        if (user_id > 0) {
            // Create session
            const session_id = try std.fmt.allocPrint(self.allocator, "session_{d}", .{user_id});
            try self.sessions.put(session_id, user_id);

            return user_id;
        }

        return error.InvalidCredentials;
    }

    pub fn validateSession(self: *Self, session_id: []const u8) ?u32 {
        return self.sessions.get(session_id);
    }

    pub fn logout(self: *Self, session_id: []const u8) void {
        _ = self.sessions.remove(session_id);
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
