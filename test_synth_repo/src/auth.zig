const std = @import("std");

pub const User = struct {
    name: []const u8,
    password: []const u8,

    pub fn init(name: []const u8, password: []const u8) User {
        return User{
            .name = name,
            .password = password,
        };
    }

    pub fn authenticate(self: User, password: []const u8) bool {
        return std.mem.eql(u8, self.password, password);
    }
};
