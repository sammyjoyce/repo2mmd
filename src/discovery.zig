const std = @import("std");

pub const Language = enum {
    Zig,
    C,
    Ts,
    Unknown,
};

pub const SourceUnit = struct {
    path: []const u8,
    lang: Language,
    module_id: []const u8,
    is_ignored: bool = false,
};

const UnitList = std.array_list.Managed(SourceUnit);

pub const Error = error{
    Unimplemented,
    Io,
    InvalidPath,
} || std.mem.Allocator.Error || std.fs.Dir.Iterator.Error;

pub fn scan(allocator: std.mem.Allocator, root: []const u8) Error![]SourceUnit {
    if (root.len == 0) return Error.InvalidPath;

    var dir = std.fs.cwd().openDir(root, .{ .iterate = true, .access_sub_paths = true }) catch |err| {
        return switch (err) {
            error.FileNotFound, error.NotDir => Error.InvalidPath,
            else => Error.Io,
        };
    };
    defer dir.close();

    var units = UnitList.init(allocator);
    errdefer deinitUnitsInternal(allocator, units.items);

    try walkDir(allocator, &dir, "", &units);

    // readdir order differs between filesystems; sort so output is deterministic.
    std.mem.sort(SourceUnit, units.items, {}, struct {
        fn lessThan(_: void, a: SourceUnit, b: SourceUnit) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    return try units.toOwnedSlice();
}

pub fn deinitUnits(allocator: std.mem.Allocator, units: []SourceUnit) void {
    deinitUnitsInternal(allocator, units);
    allocator.free(units);
}

fn walkDir(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    rel_path: []const u8,
    out_units: *UnitList,
) Error!void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                if (isSkippedDir(entry.name)) continue;
                const child_rel = try joinPath(allocator, rel_path, entry.name);
                defer allocator.free(child_rel);

                var child_dir = dir.openDir(entry.name, .{ .iterate = true, .access_sub_paths = true }) catch {
                    continue;
                };
                defer child_dir.close();

                try walkDir(allocator, &child_dir, child_rel, out_units);
            },
            .file => {
                const language = detectLanguage(entry.name);
                if (language == .Unknown) continue;

                const rel_file = try joinPath(allocator, rel_path, entry.name);

                const module_id = try deriveModuleId(allocator, rel_file);

                const unit = SourceUnit{
                    .path = rel_file,
                    .lang = language,
                    .module_id = module_id,
                    .is_ignored = shouldIgnore(rel_file),
                };

                try out_units.append(unit);
            },
            else => {},
        }
    }
}

fn detectLanguage(path: []const u8) Language {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return .Unknown;

    if (std.ascii.eqlIgnoreCase(ext, ".zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(ext, ".c") or std.ascii.eqlIgnoreCase(ext, ".h")) return .C;
    if (std.ascii.eqlIgnoreCase(ext, ".ts") or std.ascii.eqlIgnoreCase(ext, ".tsx")) return .Ts;

    return .Unknown;
}

/// Hidden directories (.git, .zig-cache) and build or dependency output.
fn isSkippedDir(name: []const u8) bool {
    if (name.len > 0 and name[0] == '.') return true;
    const skipped = [_][]const u8{ "zig-out", "zig-cache", "node_modules" };
    for (skipped) |skipped_name| {
        if (std.mem.eql(u8, name, skipped_name)) return true;
    }
    return false;
}

fn shouldIgnore(_: []const u8) bool {
    return false;
}

fn deriveModuleId(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]u8 {
    if (std.mem.lastIndexOfScalar(u8, path, std.fs.path.sep)) |idx| {
        if (idx == 0) return allocator.dupe(u8, ".");
        return allocator.dupe(u8, path[0..idx]);
    }
    return allocator.dupe(u8, "");
}

fn joinPath(allocator: std.mem.Allocator, base: []const u8, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (base.len == 0) return allocator.dupe(u8, name);
    return std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ base, std.fs.path.sep, name });
}

fn deinitUnitsInternal(allocator: std.mem.Allocator, units: []SourceUnit) void {
    for (units) |unit| {
        allocator.free(unit.path);
        allocator.free(unit.module_id);
    }
}
