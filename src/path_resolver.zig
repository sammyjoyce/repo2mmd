const std = @import("std");
const builtin = @import("builtin");

pub const EnvMap = std.process.EnvMap;

/// Options shared by the resolver helpers.
pub const Options = struct {
    env_map: ?*const EnvMap = null,
    cache_dir_override: ?[]const u8 = null,
    config_dir_override: ?[]const u8 = null,
    data_dir_override: ?[]const u8 = null,
    plugin_dirs_override: ?[]const []const u8 = null,
    app_name: []const u8 = "repo2mmd",
    legacy_root: []const u8 = ".repo2mmd",
};

/// Set of resolved destinations that migrateLegacyPaths operates on.
pub const PathSet = struct {
    cache_dir: []const u8,
    config_dir: []const u8,
    data_dir: []const u8,
    plugin_dirs: []const []const u8,
};

pub const MigrationResult = struct {
    cache_migrated: bool = false,
    data_migrated: bool = false,
    plugins_migrated: bool = false,
    config_migrated: bool = false,
};

pub const Error = std.mem.Allocator.Error || error{
    MissingHome,
    InvalidLegacyPath,
};

pub fn getCacheDir(allocator: std.mem.Allocator, options: Options) Error![]u8 {
    if (options.cache_dir_override) |override| {
        return adoptPath(allocator, options, override);
    }

    if (try envLookupOwned(allocator, options, "REPO2MMD_CACHE_DIR")) |env_path| {
        defer allocator.free(env_path);
        return adoptPath(allocator, options, env_path);
    }

    if (try envLookupOwned(allocator, options, "XDG_CACHE_HOME")) |xdg_cache| {
        defer allocator.free(xdg_cache);
        if (xdg_cache.len > 0) {
            const joined = try std.fs.path.join(allocator, &[_][]const u8{ xdg_cache, options.app_name });
            return ensureAbsolute(allocator, joined);
        }
    }

    const home = try getHomeDir(allocator, options);
    defer allocator.free(home);

    const fallback = try std.fs.path.join(allocator, &[_][]const u8{ home, ".cache", options.app_name });
    return ensureAbsolute(allocator, fallback);
}

pub fn getConfigDir(allocator: std.mem.Allocator, options: Options) Error![]u8 {
    if (options.config_dir_override) |override| {
        return adoptPath(allocator, options, override);
    }

    if (try envLookupOwned(allocator, options, "REPO2MMD_CONFIG_DIR")) |env_dir| {
        defer allocator.free(env_dir);
        return adoptPath(allocator, options, env_dir);
    }

    if (try envLookupOwned(allocator, options, "REPO2MMD_CONFIG")) |config_file| {
        defer allocator.free(config_file);
        if (std.fs.path.dirname(config_file)) |dir| {
            return adoptPath(allocator, options, dir);
        }
    }

    switch (builtin.os.tag) {
        .windows => {
            if (try envLookupOwned(allocator, options, "APPDATA")) |appdata| {
                defer allocator.free(appdata);
                const dest = try std.fs.path.join(allocator, &[_][]const u8{ appdata, options.app_name });
                return ensureAbsolute(allocator, dest);
            }
        },
        .macos => {
            const home = try getHomeDir(allocator, options);
            defer allocator.free(home);
            const dest = try std.fs.path.join(allocator, &[_][]const u8{ home, "Library", "Application Support", options.app_name });
            return ensureAbsolute(allocator, dest);
        },
        else => {},
    }

    if (try envLookupOwned(allocator, options, "XDG_CONFIG_HOME")) |xdg_config| {
        defer allocator.free(xdg_config);
        if (xdg_config.len > 0) {
            const dest = try std.fs.path.join(allocator, &[_][]const u8{ xdg_config, options.app_name });
            return ensureAbsolute(allocator, dest);
        }
    }

    const home = try getHomeDir(allocator, options);
    defer allocator.free(home);
    const fallback = try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", options.app_name });
    return ensureAbsolute(allocator, fallback);
}

pub fn getDataDir(allocator: std.mem.Allocator, options: Options) Error![]u8 {
    if (options.data_dir_override) |override| {
        return adoptPath(allocator, options, override);
    }

    if (try envLookupOwned(allocator, options, "REPO2MMD_DATA_DIR")) |env_dir| {
        defer allocator.free(env_dir);
        return adoptPath(allocator, options, env_dir);
    }

    if (try envLookupOwned(allocator, options, "XDG_DATA_HOME")) |xdg_data| {
        defer allocator.free(xdg_data);
        if (xdg_data.len > 0) {
            const dest = try std.fs.path.join(allocator, &[_][]const u8{ xdg_data, options.app_name });
            return ensureAbsolute(allocator, dest);
        }
    }

    switch (builtin.os.tag) {
        .windows => {
            if (try envLookupOwned(allocator, options, "LOCALAPPDATA")) |local_app| {
                defer allocator.free(local_app);
                const dest = try std.fs.path.join(allocator, &[_][]const u8{ local_app, options.app_name });
                return ensureAbsolute(allocator, dest);
            }
        },
        .macos => {
            const home = try getHomeDir(allocator, options);
            defer allocator.free(home);
            const dest = try std.fs.path.join(allocator, &[_][]const u8{ home, "Library", "Application Support", options.app_name });
            return ensureAbsolute(allocator, dest);
        },
        else => {},
    }

    const home = try getHomeDir(allocator, options);
    defer allocator.free(home);
    const fallback = try std.fs.path.join(allocator, &[_][]const u8{ home, ".local", "share", options.app_name });
    return ensureAbsolute(allocator, fallback);
}

pub fn getPluginDirs(allocator: std.mem.Allocator, options: Options) Error![][]u8 {
    if (options.plugin_dirs_override) |overrides| {
        return adoptPluginOverrides(allocator, options, overrides);
    }

    if (try envLookupOwned(allocator, options, "REPO2MMD_PLUGIN_DIRS")) |raw| {
        defer allocator.free(raw);
        const list = try parsePathList(allocator, options, raw);
        if (list.len > 0) {
            return list;
        }
        freeDirList(allocator, list);
    }

    var list = std.ArrayList([]u8){};
    errdefer freeDirArrayList(&list, allocator);

    const data_dir = try getDataDir(allocator, options);
    defer allocator.free(data_dir);

    const candidate = try std.fs.path.join(allocator, &[_][]const u8{ data_dir, "plugins" });
    const absolute = try ensureAbsolute(allocator, candidate);
    try list.append(allocator, absolute);

    return list.toOwnedSlice(allocator);
}

pub fn migrateLegacyPaths(
    allocator: std.mem.Allocator,
    options: Options,
    paths: PathSet,
) Error!MigrationResult {
    const base = try adoptPath(allocator, options, options.legacy_root);
    defer allocator.free(base);

    try assertAbsolute(paths.cache_dir);
    try assertAbsolute(paths.config_dir);
    try assertAbsolute(paths.data_dir);
    for (paths.plugin_dirs) |dir| try assertAbsolute(dir);

    var result = MigrationResult{};

    if (try migrateLegacyDir(allocator, base, "cache", paths.cache_dir)) result.cache_migrated = true;
    if (try migrateLegacyDir(allocator, base, "data", paths.data_dir)) result.data_migrated = true;

    if (paths.plugin_dirs.len > 0) {
        if (try migrateLegacyDir(allocator, base, "plugins", paths.plugin_dirs[0])) {
            result.plugins_migrated = true;
        }
    }

    const legacy_config = try std.fs.path.join(allocator, &[_][]const u8{ base, "repo2mmd.toml" });
    defer allocator.free(legacy_config);

    const config_dest = try std.fs.path.join(allocator, &[_][]const u8{ paths.config_dir, "repo2mmd.toml" });
    defer allocator.free(config_dest);

    if (try migrateLegacyFile(legacy_config, config_dest)) {
        result.config_migrated = true;
    }

    return result;
}

pub fn freeDirList(allocator: std.mem.Allocator, dirs: [][]u8) void {
    for (dirs) |dir| allocator.free(dir);
    allocator.free(dirs);
}

fn migrateLegacyDir(
    allocator: std.mem.Allocator,
    base: []const u8,
    name: []const u8,
    destination: []const u8,
) Error!bool {
    const legacy_path = try std.fs.path.join(allocator, &[_][]const u8{ base, name });
    defer allocator.free(legacy_path);

    if (std.mem.eql(u8, legacy_path, destination)) return false;

    var dir = std.fs.openDirAbsolute(legacy_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.InvalidLegacyPath,
    };
    dir.close();

    try ensureParentExists(destination);

    std.fs.renameAbsolute(legacy_path, destination) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => return error.InvalidLegacyPath,
    };

    return true;
}

fn migrateLegacyFile(src: []const u8, dest: []const u8) Error!bool {
    const file = std.fs.openFileAbsolute(src, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.InvalidLegacyPath,
    };
    file.close();

    if (std.fs.accessAbsolute(dest, .{})) |_| {
        return false;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return error.InvalidLegacyPath,
    }

    try ensureParentExists(dest);

    std.fs.renameAbsolute(src, dest) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => return error.InvalidLegacyPath,
    };

    return true;
}

fn adoptPluginOverrides(
    allocator: std.mem.Allocator,
    options: Options,
    overrides: []const []const u8,
) Error![][]u8 {
    var list = std.ArrayList([]u8){};
    errdefer freeDirArrayList(&list, allocator);

    for (overrides) |entry| {
        if (entry.len == 0) continue;
        const path = try adoptPath(allocator, options, entry);
        try list.append(allocator, path);
    }

    return list.toOwnedSlice(allocator);
}

fn parsePathList(
    allocator: std.mem.Allocator,
    options: Options,
    raw: []const u8,
) Error![][]u8 {
    var list = std.ArrayList([]u8){};
    errdefer freeDirArrayList(&list, allocator);

    const delimiter: u8 = switch (builtin.os.tag) {
        .windows => ';',
        else => ':',
    };

    var it = std.mem.splitScalar(u8, raw, delimiter);
    while (it.next()) |segment| {
        if (segment.len == 0) continue;
        const path = try adoptPath(allocator, options, segment);
        try list.append(allocator, path);
    }

    return list.toOwnedSlice(allocator);
}

fn adoptPath(allocator: std.mem.Allocator, options: Options, raw: []const u8) Error![]u8 {
    return ensureAbsolute(allocator, try expandUserPath(allocator, options, raw));
}

fn expandUserPath(allocator: std.mem.Allocator, options: Options, raw: []const u8) Error![]u8 {
    if (raw.len == 0) return allocator.dupe(u8, raw);

    if (raw[0] == '~' and (raw.len == 1 or raw[1] == '/' or raw[1] == std.fs.path.sep)) {
        const home = try getHomeDir(allocator, options);
        defer allocator.free(home);

        if (raw.len == 1) {
            return allocator.dupe(u8, home);
        }

        if (raw.len == 2) {
            return allocator.dupe(u8, home);
        }

        const remainder = raw[2..];
        if (remainder.len == 0) {
            return allocator.dupe(u8, home);
        }

        return std.fs.path.join(allocator, &[_][]const u8{ home, remainder });
    }

    return allocator.dupe(u8, raw);
}

fn ensureAbsolute(allocator: std.mem.Allocator, path: []u8) Error![]u8 {
    if (std.fs.path.isAbsolute(path)) return path;

    const cwd = std.process.getCwdAlloc(allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidLegacyPath,
    };
    defer allocator.free(cwd);

    const joined = try std.fs.path.join(allocator, &[_][]const u8{ cwd, path });
    allocator.free(path);
    return joined;
}

fn getHomeDir(allocator: std.mem.Allocator, options: Options) Error![]u8 {
    if (builtin.os.tag == .windows) {
        if (try envLookupOwned(allocator, options, "USERPROFILE")) |profile| {
            return profile;
        }
    }

    if (try envLookupOwned(allocator, options, "HOME")) |home| {
        return home;
    }

    if (builtin.os.tag == .windows) {
        if (try envLookupOwned(allocator, options, "HOMEPATH")) |home_path| {
            defer allocator.free(home_path);
            if (try envLookupOwned(allocator, options, "HOMEDRIVE")) |drive| {
                defer allocator.free(drive);
                return std.fs.path.join(allocator, &[_][]const u8{ drive, home_path });
            }
            return allocator.dupe(u8, home_path);
        }
    }

    return error.MissingHome;
}

fn envLookupOwned(allocator: std.mem.Allocator, options: Options, name: []const u8) Error!?[]u8 {
    if (options.env_map) |env| {
        if (env.*.get(name)) |value| {
            const copy = try allocator.dupe(u8, value);
            return @as(?[]u8, copy);
        }
        return null;
    }

    const value = std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        error.InvalidWtf8 => return error.InvalidLegacyPath,
        error.OutOfMemory => return error.OutOfMemory,
    };
    return @as(?[]u8, value);
}

fn ensureParentExists(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    try ensureParentExists(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return error.InvalidLegacyPath,
    };
}

fn assertAbsolute(path: []const u8) Error!void {
    if (!std.fs.path.isAbsolute(path)) return error.InvalidLegacyPath;
}

fn freeDirArrayList(list: *std.ArrayList([]u8), allocator: std.mem.Allocator) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

// -----------------
// Tests
// -----------------

test "cache dir respects overrides" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    try env.put("HOME", "/home/tester");

    const options = Options{
        .env_map = &env,
        .cache_dir_override = "/tmp/cache",
    };

    const path = try getCacheDir(std.testing.allocator, options);
    defer std.testing.allocator.free(path);

    try std.testing.expect(std.fs.path.isAbsolute(path));
    try std.testing.expectEqualStrings("/tmp/cache", path);
}

test "cache dir uses env override with tilde" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    try env.put("HOME", "/home/tester");
    try env.put("REPO2MMD_CACHE_DIR", "~/custom-cache");

    const options = Options{ .env_map = &env };
    const path = try getCacheDir(std.testing.allocator, options);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/home/tester/custom-cache", path);
}

test "config dir uses REPO2MMD_CONFIG parent" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    try env.put("HOME", "/home/tester");
    try env.put("REPO2MMD_CONFIG", "/var/lib/repo2mmd/settings.toml");

    const options = Options{ .env_map = &env };
    const path = try getConfigDir(std.testing.allocator, options);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/var/lib/repo2mmd", path);
}

test "plugin dirs parse list" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    try env.put("HOME", "/home/tester");
    try env.put("REPO2MMD_PLUGIN_DIRS", "/opt/plugins:/home/tester/.local/plugins");

    const options = Options{ .env_map = &env };
    const dirs = try getPluginDirs(std.testing.allocator, options);
    defer freeDirList(std.testing.allocator, dirs);

    try std.testing.expectEqual(@as(usize, 2), dirs.len);
    try std.testing.expectEqualStrings("/opt/plugins", dirs[0]);
    try std.testing.expectEqualStrings("/home/tester/.local/plugins", dirs[1]);
}

test "plugin dirs default to data directory" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    try env.put("HOME", "/home/tester");
    try env.put("XDG_DATA_HOME", "/xdg/data");

    const options = Options{ .env_map = &env };
    const dirs = try getPluginDirs(std.testing.allocator, options);
    defer freeDirList(std.testing.allocator, dirs);

    try std.testing.expectEqual(@as(usize, 1), dirs.len);
    try std.testing.expectEqualStrings("/xdg/data/repo2mmd/plugins", dirs[0]);
}

test "migrate legacy paths moves directories and config" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath(".repo2mmd/cache");
    try tmp.dir.makePath(".repo2mmd/data");
    try tmp.dir.makePath(".repo2mmd/plugins");

    const config_content = "cache = true\n";
    {
        var config_file = try tmp.dir.createFile(".repo2mmd/repo2mmd.toml", .{});
        defer config_file.close();
        try config_file.writeAll(config_content);
    }

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const legacy_root = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ tmp_path, ".repo2mmd" });
    defer std.testing.allocator.free(legacy_root);

    const cache_dest = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ tmp_path, "xdg", "cache", "repo2mmd" });
    defer std.testing.allocator.free(cache_dest);

    const data_dest = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ tmp_path, "xdg", "data", "repo2mmd" });
    defer std.testing.allocator.free(data_dest);

    const config_dest = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ tmp_path, "xdg", "config", "repo2mmd" });
    defer std.testing.allocator.free(config_dest);

    const plugin_dest = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ data_dest, "plugins" });
    defer std.testing.allocator.free(plugin_dest);

    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const options = Options{
        .env_map = &env,
        .legacy_root = legacy_root,
    };

    const paths = PathSet{
        .cache_dir = cache_dest,
        .config_dir = config_dest,
        .data_dir = data_dest,
        .plugin_dirs = &[_][]const u8{plugin_dest},
    };

    const result = try migrateLegacyPaths(std.testing.allocator, options, paths);
    try std.testing.expect(result.cache_migrated);
    try std.testing.expect(result.data_migrated);
    try std.testing.expect(result.plugins_migrated);
    try std.testing.expect(result.config_migrated);

    try std.testing.expectError(error.FileNotFound, tmp.dir.openDir(".repo2mmd/cache", .{}));
    var cache_dir = try std.fs.openDirAbsolute(cache_dest, .{});
    cache_dir.close();

    const moved_config_path = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ config_dest, "repo2mmd.toml" });
    defer std.testing.allocator.free(moved_config_path);
    const contents = try std.fs.cwd().readFileAlloc(std.testing.allocator, moved_config_path, config_content.len + 32);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings(config_content, contents);
}
