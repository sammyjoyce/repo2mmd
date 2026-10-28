const std = @import("std");
const crypto = std.crypto;
const hash = crypto.hash.sha2.Sha256;

pub const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
};

pub const AuthError = error{
    InvalidCredentials,
    UserNotFound,
    DatabaseError,
};

pub fn authenticate(username: []const u8, password: []const u8) AuthError!User {
    // In a real implementation, this would query a database
    if (std.mem.eql(u8, username, "admin") and std.mem.eql(u8, password, "password")) {
        return User{
            .id = 1,
            .name = "Admin User",
            .email = "admin@example.com",
        };
    }
    return AuthError.InvalidCredentials;
}

pub fn hashPassword(password: []const u8) [32]u8 {
    var hasher = hash.init(.{});
    hasher.update(password);
    return hasher.finalResult();
}

pub fn verifyPassword(password: []const u8, password_hash: [32]u8) bool {
    const computed = hashPassword(password);
    return std.mem.eql(u8, &computed, &password_hash);
}
