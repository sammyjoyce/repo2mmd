const std = @import("std");
const builtin = @import("builtin");

// Import from local modules
const auth = @import("auth.zig");
const database = @import("database.zig");

// Import with alias
const fmt = @import("std").fmt;

// Conditional imports
const debug_mode = builtin.mode == .Debug;
const debug_import = if (debug_mode) @import("std").debug else struct {};

// Function that uses debug import
pub fn useDebugImport() void {
    const debug = @import("std").debug;
    debug.print("Debug import working\n", .{});
}

// Usingnamespace with local struct
const CommonTypes = struct {
    pub const UserId = u32;
    pub const SessionId = u64;
    pub const Timestamp = i64;
};

// Note: usingnamespace at module scope not supported in this context

// Function that uses imported modules
pub fn processUser(user_id: CommonTypes.UserId) !auth.User {
    // Use imported auth module
    const user = try auth.authenticate("admin", "password");

    // Use imported database module
    var db = try database.init(std.heap.page_allocator);
    defer db.deinit();

    // Use imported fmt
    try fmt.print("Processing user: {}\n", .{user_id});

    return user;
}

// Nested imports
const container = struct {
    const inner = @import("std");
    pub const ArrayList = inner.ArrayList;
};

// Import in comptime context
comptime {
    const imported_type = @import("std").hash_map.AutoHashMap;
    _ = imported_type;
}

// Re-export imports
pub const ArrayList = @import("std").ArrayList;
pub const StringHashMap = @import("std").hash_map.StringHashMap;

// Function using CommonTypes
pub fn createSession(user_id: CommonTypes.UserId, session_id: CommonTypes.SessionId) struct {
    user_id: CommonTypes.UserId,
    session_id: CommonTypes.SessionId,
    created_at: CommonTypes.Timestamp,
} {
    const now = std.time.timestamp();
    return .{
        .user_id = user_id,
        .session_id = session_id,
        .created_at = @intCast(now),
    };
}
