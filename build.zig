const std = @import("std");
const builtin = @import("builtin");
const manifest = @import("build.zig.zon");

// Zig changes std and build APIs between minor releases, so the build accepts
// exactly the toolchain named in build.zig.zon instead of a minimum.
comptime {
    const required = std.SemanticVersion.parse(manifest.minimum_zig_version) catch unreachable;
    if (builtin.zig_version.order(required) != .eq) {
        @compileError(std.fmt.comptimePrint(
            "repo2mmd requires Zig {s} exactly (found {f}); see README.md#toolchain",
            .{ manifest.minimum_zig_version, builtin.zig_version },
        ));
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_plugins = b.option(bool, "no_plugins", "Disable dynamic plugin loading (stubs plugin interfaces)") orelse false;
    const strip = b.option(bool, "strip", "Omit debug info from the binary and plugins (release archives use this)");
    // Without NDEBUG, C asserts embed absolute __FILE__ paths even in stripped builds.
    const c_flags: []const []const u8 = if (optimize == .Debug) &.{"-std=gnu11"} else &.{ "-std=gnu11", "-DNDEBUG" };

    // Build options for conditional compilation - modules import this as "build_options"
    // to access the no_plugins flag for conditional compilation between native and stub implementations
    const build_options = b.addOptions();
    build_options.addOption(bool, "no_plugins", no_plugins);
    build_options.addOption([]const u8, "version", manifest.version);

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    root_module.addOptions("build_options", build_options);

    const ir_module = b.createModule(.{
        .root_source_file = b.path("src/ir.zig"),
        .target = target,
        .optimize = optimize,
    });

    const discovery_module = b.createModule(.{
        .root_source_file = b.path("src/discovery.zig"),
        .target = target,
        .optimize = optimize,
    });

    const diag_module = b.createModule(.{
        .root_source_file = b.path("src/diag.zig"),
        .target = target,
        .optimize = optimize,
    });

    const plugin_loader_module = b.createModule(.{
        .root_source_file = b.path("src/plugin_loader.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin_loader_module.addIncludePath(b.path("include"));
    plugin_loader_module.addImport("ir", ir_module);
    plugin_loader_module.addImport("diag", diag_module);
    plugin_loader_module.addOptions("build_options", build_options);

    const json_emitter_module = b.createModule(.{
        .root_source_file = b.path("src/json_emitter.zig"),
        .target = target,
        .optimize = optimize,
    });
    json_emitter_module.addImport("ir", ir_module);

    const mermaid_emitter_module = b.createModule(.{
        .root_source_file = b.path("src/mermaid_emitter.zig"),
        .target = target,
        .optimize = optimize,
    });
    mermaid_emitter_module.addImport("ir", ir_module);

    const plugin_harness_module = b.createModule(.{
        .root_source_file = b.path("src/plugin_harness.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin_harness_module.addIncludePath(b.path("include"));
    plugin_harness_module.addImport("plugin_loader", plugin_loader_module);
    plugin_harness_module.addImport("ir", ir_module);
    plugin_harness_module.addImport("diag", diag_module);

    const path_resolver_module = b.createModule(.{
        .root_source_file = b.path("src/path_resolver.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cache_mgr_module = b.createModule(.{
        .root_source_file = b.path("src/cache.zig"),
        .target = target,
        .optimize = optimize,
    });
    cache_mgr_module.addImport("ir", ir_module);
    cache_mgr_module.addImport("diag", diag_module);
    cache_mgr_module.addImport("path_resolver", path_resolver_module);

    const tsconfig_resolver_module = b.createModule(.{
        .root_source_file = b.path("src/tsconfig_resolver.zig"),
        .target = target,
        .optimize = optimize,
    });

    const diagnostics_engine_module = b.createModule(.{
        .root_source_file = b.path("src/diagnostics_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    diagnostics_engine_module.addImport("ir", ir_module);
    diagnostics_engine_module.addImport("diag", diag_module);

    const resolver_module = b.createModule(.{
        .root_source_file = b.path("src/resolver.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_module.addImport("ir", ir_module);
    resolver_module.addImport("diag", diag_module);
    resolver_module.addImport("diagnostics_engine", diagnostics_engine_module);

    const grouping_module = b.createModule(.{
        .root_source_file = b.path("src/grouping.zig"),
        .target = target,
        .optimize = optimize,
    });
    grouping_module.addImport("ir", ir_module);
    grouping_module.addImport("diag", diag_module);

    const pruning_module = b.createModule(.{
        .root_source_file = b.path("src/pruning.zig"),
        .target = target,
        .optimize = optimize,
    });
    pruning_module.addImport("ir", ir_module);
    pruning_module.addImport("diag", diag_module);

    const scheduler_module = b.createModule(.{
        .root_source_file = b.path("src/scheduler.zig"),
        .target = target,
        .optimize = optimize,
    });
    scheduler_module.addImport("discovery", discovery_module);
    scheduler_module.addImport("ir", ir_module);
    scheduler_module.addImport("diag", diag_module);
    scheduler_module.addImport("plugin_loader", plugin_loader_module);
    scheduler_module.addImport("resolver", resolver_module);
    scheduler_module.addImport("path_resolver", path_resolver_module);
    scheduler_module.addIncludePath(b.path("include"));

    root_module.addImport("ir", ir_module);
    root_module.addImport("discovery", discovery_module);
    root_module.addImport("diag", diag_module);
    root_module.addImport("cache_mgr", cache_mgr_module);
    root_module.addImport("scheduler", scheduler_module);
    root_module.addImport("json_emitter", json_emitter_module);
    root_module.addImport("mermaid_emitter", mermaid_emitter_module);
    root_module.addImport("plugin_loader", plugin_loader_module);
    root_module.addImport("tsconfig_resolver", tsconfig_resolver_module);
    root_module.addImport("path_resolver", path_resolver_module);

    const exe = b.addExecutable(.{
        .name = "repo2mmd",
        .root_module = root_module,
    });

    // Link libc for plugin support
    exe.linkLibC();

    b.installArtifact(exe);

    // Language plugins: C shared libraries built by the pinned Zig toolchain
    // (no system cc), installed where the binary looks for them by default.
    const plugins_step = b.step("plugins", "Build all plugins");
    const tree_sitter = b.addLibrary(.{
        .name = "tree-sitter",
        .linkage = .static,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .strip = strip, .link_libc = true, .pic = true }),
    });
    tree_sitter.addCSourceFile(.{ .file = b.path("third_party/tree-sitter/lib/src/lib.c"), .flags = c_flags });
    tree_sitter.addIncludePath(b.path("third_party/tree-sitter/lib/include"));
    tree_sitter.addIncludePath(b.path("third_party/tree-sitter/lib/src"));
    tree_sitter.root_module.addCMacro("_POSIX_C_SOURCE", "200112L");
    tree_sitter.root_module.addCMacro("_DEFAULT_SOURCE", "");
    tree_sitter.root_module.addCMacro("_DARWIN_C_SOURCE", "");

    const PluginSpec = struct {
        name: []const u8,
        sources: []const []const u8,
        include_paths: []const []const u8,
        uses_tree_sitter: bool,
        test_only: bool = false,
    };
    const plugin_specs = [_]PluginSpec{
        .{
            .name = "dummy",
            .sources = &.{"plugins/dummy/dummy_frontend.c"},
            .include_paths = &.{"include"},
            .uses_tree_sitter = false,
            .test_only = true,
        },
        .{
            .name = "typescript",
            .sources = &.{
                "plugins/typescript/typescript_frontend_tree_sitter.c",
                "third_party/tree-sitter-typescript/typescript/src/parser.c",
                "third_party/tree-sitter-typescript/typescript/src/scanner.c",
                "third_party/tree-sitter-typescript/tsx/src/parser.c",
                "third_party/tree-sitter-typescript/tsx/src/scanner.c",
            },
            .include_paths = &.{ "include", "third_party/tree-sitter/lib/include", "third_party/tree-sitter-typescript/bindings/c", "third_party/tree-sitter-typescript/typescript/src" },
            .uses_tree_sitter = true,
        },
        .{
            .name = "zig",
            .sources = &.{
                "plugins/zig/zig_frontend_enhanced.c",
                "third_party/tree-sitter-zig/src/parser.c",
            },
            .include_paths = &.{ "include", "third_party/tree-sitter/lib/include", "third_party/tree-sitter-zig/src" },
            .uses_tree_sitter = true,
        },
    };
    for (plugin_specs) |spec| {
        const plugin = b.addLibrary(.{
            .name = b.fmt("repo2mmd_{s}", .{spec.name}),
            .linkage = .dynamic,
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .strip = strip, .link_libc = true, .pic = true }),
        });
        plugin.addCSourceFiles(.{ .files = spec.sources, .flags = c_flags });
        for (spec.include_paths) |include_path| plugin.addIncludePath(b.path(include_path));
        if (spec.uses_tree_sitter) plugin.linkLibrary(tree_sitter);
        const install_plugin = b.addInstallFileWithDir(
            plugin.getEmittedBin(),
            .{ .custom = "lib/repo2mmd/plugins" },
            b.fmt("librepo2mmd_{s}.so", .{spec.name}),
        );
        plugins_step.dependOn(&install_plugin.step);
        if (!spec.test_only) b.getInstallStep().dependOn(&install_plugin.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run repo2mmd");
    run_step.dependOn(&run_cmd.step);

    const fmt = b.addFmt(.{
        .paths = &.{ "build.zig", "src", "test" },
        .check = false,
    });
    const fmt_step = b.step("fmt", "Format Zig sources");
    fmt_step.dependOn(&fmt.step);

    const fmt_check = b.addFmt(.{
        .paths = &.{ "build.zig", "src", "test" },
        .check = true,
    });
    const fmt_check_step = b.step("fmt-check", "Check Zig formatting");
    fmt_check_step.dependOn(&fmt_check.step);

    // Build compilation check for ZLS Build-On-Save
    // See: https://zigtools.org/zls/guides/build-on-save/
    const check_compile = b.addExecutable(.{
        .name = "repo2mmd",
        .root_module = root_module,
    });
    const check_step = b.step("check", "Check compilation (ZLS Build-On-Save)");
    check_step.dependOn(&check_compile.step);

    // Add OpenCLI generation step using comptime
    const opencli_exe = b.addExecutable(.{
        .name = "generate-opencli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate_opencli.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });

    const opencli_run = b.addRunArtifact(opencli_exe);
    opencli_run.addArg("zig-out/opencli.json");

    const opencli_step = b.step("opencli", "Generate OpenCLI specification");
    opencli_step.dependOn(&opencli_run.step);

    // Fixtures test step - separate from main test suite
    const fixtures_test_module = b.createModule(.{
        .root_source_file = b.path("test/fixtures_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    fixtures_test_module.addImport("ir", ir_module);
    fixtures_test_module.addImport("discovery", discovery_module);
    fixtures_test_module.addImport("diag", diag_module);
    fixtures_test_module.addImport("scheduler", scheduler_module);
    fixtures_test_module.addImport("json_emitter", json_emitter_module);
    fixtures_test_module.addImport("mermaid_emitter", mermaid_emitter_module);

    const fixtures_tests = b.addTest(.{ .root_module = fixtures_test_module });
    const fixtures_test_cmd = b.addRunArtifact(fixtures_tests);
    const fixtures_test_step = b.step("test-fixtures", "Run fixtures test suite (less frequent)");
    fixtures_test_step.dependOn(&fixtures_test_cmd.step);

    // Plugin loader tests

    var plugin_loader_test_step: ?*std.Build.Step = null;
    if (!no_plugins) {
        const plugin_loader_test_module = b.createModule(.{
            .root_source_file = b.path("test/plugin_loader_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        plugin_loader_test_module.addIncludePath(b.path("include"));
        plugin_loader_test_module.addImport("plugin_loader", plugin_loader_module);
        plugin_loader_test_module.addImport("plugin_harness", plugin_harness_module);

        const plugin_loader_tests = b.addTest(.{ .root_module = plugin_loader_test_module });
        plugin_loader_tests.addIncludePath(b.path("include"));
        plugin_loader_tests.linkLibC();

        const plugin_loader_test_cmd = b.addRunArtifact(plugin_loader_tests);
        const step = b.step("test-plugin-loader", "Run plugin loader tests");
        plugin_loader_test_cmd.step.dependOn(plugins_step);
        step.dependOn(&plugin_loader_test_cmd.step);
        plugin_loader_test_step = step;
    }

    // Main test module (defined after plugin modules are available)
    const test_module = b.createModule(.{
        .root_source_file = b.path("test/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addIncludePath(b.path("include"));
    test_module.addImport("ir", ir_module);
    test_module.addImport("discovery", discovery_module);
    test_module.addImport("diag", diag_module);
    test_module.addImport("scheduler", scheduler_module);
    test_module.addImport("json_emitter", json_emitter_module);
    test_module.addImport("mermaid_emitter", mermaid_emitter_module);
    test_module.addImport("cache", cache_mgr_module);
    test_module.addImport("plugin_loader", plugin_loader_module);
    test_module.addImport("plugin_harness", plugin_harness_module);
    test_module.addImport("resolver", resolver_module);
    test_module.addImport("grouping", grouping_module);
    test_module.addImport("pruning", pruning_module);
    test_module.addImport("diagnostics_engine", diagnostics_engine_module);
    const tests = b.addTest(.{ .root_module = test_module });
    tests.linkLibC();
    const test_cmd = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Zig test suite");
    test_step.dependOn(&test_cmd.step);

    // Integration step that runs main tests + fixtures (for CI)
    const integration_step = b.step("test-integration", "Run all tests including fixtures");
    integration_step.dependOn(test_step);
    integration_step.dependOn(fixtures_test_step);
    if (plugin_loader_test_step) |step| {
        integration_step.dependOn(step);
    }
}
