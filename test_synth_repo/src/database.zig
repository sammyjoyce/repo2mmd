const std = @import("std");

pub const Database = struct {
    url: []const u8,

    pub fn connect(url: []const u8) !Database {
        if (url.len == 0) {
            return error.EmptyUrl;
        }
        return Database{
            .url = url,
        };
    }

    pub fn query(self: Database, sql: []const u8) ![]const u8 {
        _ = self;
        _ = sql;
        return "result";
    }
};
