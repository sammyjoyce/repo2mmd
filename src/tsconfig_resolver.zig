const std = @import("std");
const json = std.json;

/// TypeScript configuration resolver
pub const TsConfigResolver = struct {
    allocator: std.mem.Allocator,
    config: ?TsConfig,

    pub const TsConfig = struct {
        compiler_options: CompilerOptions,

        pub const CompilerOptions = struct {
            base_url: ?[]const u8 = null,
            paths: std.json.ObjectMap = std.json.ObjectMap.init(std.heap.page_allocator),
            module_resolution: ?[]const u8 = null,

            pub fn deinit(self: *@This()) void {
                self.paths.deinit();
            }
        };

        pub fn deinit(self: *@This()) void {
            self.compiler_options.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) TsConfigResolver {
        return .{
            .allocator = allocator,
            .config = null,
        };
    }

    pub fn deinit(self: *TsConfigResolver) void {
        if (self.config) |*config| {
            config.deinit();
        }
    }

    /// Load tsconfig.json from the given directory
    pub fn load(self: *TsConfigResolver, project_root: []const u8) !void {
        const tsconfig_path = try std.fs.path.join(self.allocator, &.{ project_root, "tsconfig.json" });
        defer self.allocator.free(tsconfig_path);

        const file = std.fs.cwd().openFile(tsconfig_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // No tsconfig.json found, use defaults
                self.config = TsConfig{
                    .compiler_options = .{
                        .module_resolution = null,
                        .base_url = null,
                    },
                };
                return;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB limit
        defer self.allocator.free(content);

        const parsed = try json.parseFromSliceLeaky(TsConfig, self.allocator, content, .{
            .ignore_unknown_fields = true,
        });

        self.config = parsed;
    }

    /// Resolve a module path according to tsconfig.json paths mapping
    pub fn resolveModule(self: *const TsConfigResolver, module_path: []const u8, from_file: []const u8) !?[]const u8 {
        _ = from_file; // TODO: use from_file for relative path resolution
        const config = self.config orelse return null;
        const compiler_options = config.compiler_options;

        // Check if module path matches any of the configured paths
        const path_it = compiler_options.paths.iterator();
        while (path_it.next()) |entry| {
            const pattern = entry.key_ptr.*;
            const targets = entry.value_ptr.*;

            // Simple pattern matching - support "*" wildcard
            if (std.mem.indexOf(u8, pattern, "*")) |wildcard_pos| {
                const prefix = pattern[0..wildcard_pos];
                const suffix = pattern[wildcard_pos + 1 ..];

                if (std.mem.startsWith(u8, module_path, prefix) and
                    (suffix.len == 0 or std.mem.endsWith(u8, module_path, suffix)))
                {

                    // Extract the wildcard part
                    const wildcard_part = module_path[prefix.len .. module_path.len - suffix.len];

                    // Apply to each target
                    if (targets.array.len > 0) {
                        const target = targets.array.items[0].string;
                        var resolved = try self.allocator.alloc(u8, target.len + wildcard_part.len);
                        std.mem.copy(u8, resolved, target);

                        // Replace "*" with wildcard_part
                        if (std.mem.indexOf(u8, target, "*")) |target_wildcard| {
                            const before_wildcard = target[0..target_wildcard];
                            const after_wildcard = target[target_wildcard + 1 ..];

                            resolved = try self.allocator.realloc(resolved, before_wildcard.len + wildcard_part.len + after_wildcard.len);
                            std.mem.copy(u8, resolved, before_wildcard);
                            std.mem.copy(u8, resolved[before_wildcard.len..], wildcard_part);
                            std.mem.copy(u8, resolved[before_wildcard.len + wildcard_part.len ..], after_wildcard);
                        }

                        return resolved;
                    }
                }
            } else if (std.mem.eql(u8, module_path, pattern)) {
                // Exact match
                if (targets.array.len > 0) {
                    const target = targets.array.items[0].string;
                    return self.allocator.dupe(u8, target);
                }
            }
        }

        // If no path mapping matches, try baseUrl resolution
        if (compiler_options.base_url) |base_url| {
            if (!std.mem.startsWith(u8, module_path, ".")) {
                // Non-relative import, try baseUrl
                return std.fs.path.join(self.allocator, &.{ base_url, module_path });
            }
        }

        return null;
    }

    /// Get the module resolution strategy
    pub fn getModuleResolution(self: *const TsConfigResolver) []const u8 {
        const config = self.config orelse return "node";
        const compiler_options = config.compiler_options;
        return compiler_options.module_resolution orelse "node";
    }
};

test "TsConfigResolver.basic" {
    const allocator = std.testing.allocator;
    var resolver = TsConfigResolver.init(allocator);
    defer resolver.deinit();

    // Test with a sample tsconfig.json content
    const tsconfig_content =
        \\{
        \\  "compilerOptions": {
        \\    "baseUrl": "./src",
        \\    "paths": {
        \\      "@/*": ["*"],
        \\      "@auth/*": ["auth/*"],
        \\      "@db/*": ["database/*"]
        \\    },
        \\    "moduleResolution": "node"
        \\  }
        \\}
    ;

    // Create a temporary tsconfig.json file
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile("tsconfig.json", tsconfig_content);

    // Load the config
    try resolver.load(tmp_dir.dir_path);

    // Test path resolution
    const resolved1 = try resolver.resolveModule("@auth/service", "./src/index.ts");
    defer if (resolved1) |r| allocator.free(r);
    try std.testing.expectEqualStrings("auth/service", resolved1.?);

    const resolved2 = try resolver.resolveModule("./utils", "./src/index.ts");
    defer if (resolved2) |r| allocator.free(r);
    try std.testing.expect(resolved2 == null); // Relative paths not handled by baseUrl
}
