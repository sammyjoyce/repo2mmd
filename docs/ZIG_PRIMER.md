# Zig Primer for C Developers

This guide helps C developers understand how Zig is used as the build system for this C23 project.

## Table of Contents

- [Why Zig for a C Project?](#why-zig-for-a-c-project)
- [Zig as a C Compiler](#zig-as-a-c-compiler)
- [Understanding build.zig](#understanding-buildzig)
- [Understanding build.zig.zon](#understanding-buildzigzon)
- [Common Build Tasks](#common-build-tasks)
- [Zig vs Make/CMake](#zig-vs-makecmake)
- [Troubleshooting](#troubleshooting)

## Why Zig for a C Project?

Zig provides several advantages as a build system for C projects:

1. **Cross-compilation out of the box** - No need for separate toolchains
2. **Built-in C compiler** - Zig bundles Clang/LLVM
3. **Dependency management** - Via build.zig.zon
4. **Caching** - Intelligent incremental builds
5. **No separate build language** - Build scripts are written in Zig

## Zig as a C Compiler

Zig can compile C code directly:

```bash
# Compile a C file
zig cc hello.c -o hello

# With C23 standard
zig cc -std=c23 hello.c -o hello

# Cross-compile for Windows from Linux
zig cc -target x86_64-windows hello.c -o hello.exe
```

### Zig CC vs GCC/Clang

| Feature | Zig CC | GCC/Clang |
|---------|--------|-----------|
| Cross-compilation | Built-in | Requires separate toolchains |
| C23 Support | Yes (via LLVM) | Yes |
| Optimization | -O0 to -O3 | -O0 to -O3 |
| Debug Info | -g | -g |
| Static Analysis | Basic | Extensive |

## Understanding build.zig

The `build.zig` file is like a `Makefile` or `CMakeLists.txt`, but written in Zig:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable from C sources
    const exe = b.addExecutable(.{
        .name = "repo2mmd",
        .target = target,
        .optimize = optimize,
    });

    // Add C source files
    exe.addCSourceFiles(.{
        .files = &.{
            "src/main.c",
            "src/cli/args.c",
            "src/cli/help.c",
            // ... more files
        },
        .flags = &.{
            "-std=c23",
            "-Wall",
            "-Wextra",
            "-pedantic",
        },
    });

    // Link libraries
    exe.linkSystemLibrary("c");
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("pdcurses");
    } else {
        exe.linkSystemLibrary("ncurses");
    }

    // Install the executable
    b.installArtifact(exe);
}
```

### Key Concepts

1. **Build Function**: The `pub fn build()` is the entry point
2. **Build Object**: `b` provides all build functionality
3. **Artifacts**: Executables, libraries, etc.
4. **Steps**: Build tasks that can depend on each other

### Common Patterns

```zig
// Adding include directories
exe.addIncludePath(b.path("src"));
exe.addIncludePath(b.path("vendor/include"));

// Platform-specific code
if (target.result.os.tag == .windows) {
    exe.defineCMacro("PLATFORM_WINDOWS", null);
} else if (target.result.os.tag == .linux) {
    exe.defineCMacro("PLATFORM_LINUX", null);
}

// Creating a test step
const test_step = b.step("test", "Run tests");
test_step.dependOn(&exe.step);

// Custom build options
const enable_tui = b.option(bool, "enable-tui", "Enable TUI support") orelse true;
if (enable_tui) {
    exe.defineCMacro("ENABLE_TUI", null);
}
```

## Understanding build.zig.zon

The `build.zig.zon` file manages dependencies and project metadata:

```zig
.{
    .name = "repo2mmd",
    .version = "0.1.0",
    
    // Dependencies
    .dependencies = .{
        .some_lib = .{
            .url = "https://github.com/user/lib/archive/abc123.tar.gz",
            .hash = "1220abc...",
        },
    },
    
    // Paths to include in package
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "LICENSE",
        "README.md",
    },
}
```

## Common Build Tasks

### Basic Commands

```bash
# Build the project
zig build

# Build and run
zig build run

# Run tests
zig build test

# Build with optimizations
zig build -Doptimize=ReleaseSafe

# Cross-compile
zig build -Dtarget=x86_64-windows

# Install to custom prefix
zig build install --prefix ~/.local

# Clean build
rm -rf zig-cache zig-out
```

### Build Modes

| Mode | Flag | Description |
|------|------|-------------|
| Debug | (default) | No optimizations, debug info |
| ReleaseSafe | `-Doptimize=ReleaseSafe` | Optimized, safety checks |
| ReleaseFast | `-Doptimize=ReleaseFast` | Optimized, no safety |
| ReleaseSmall | `-Doptimize=ReleaseSmall` | Size-optimized |

### Adding New C Files

1. Add the file to `exe.addCSourceFiles()` in `build.zig`:
   ```zig
   exe.addCSourceFiles(.{
       .files = &.{
           // existing files...
           "src/new_module.c",
       },
       .flags = &.{ "-std=c23", "-Wall" },
   });
   ```

2. Rebuild:
   ```bash
   zig build
   ```

## Zig vs Make/CMake

### Comparison Table

| Feature | Zig | Make | CMake |
|---------|-----|------|-------|
| Language | Zig | Make syntax | CMake script |
| Cross-compilation | Built-in | Manual setup | Toolchain files |
| Dependency management | build.zig.zon | None | FetchContent/ExternalProject |
| IDE support | Growing | Excellent | Excellent |
| Learning curve | Moderate | Low | High |
| Platform detection | Automatic | Manual | Automatic |
| Parallel builds | Automatic | make -j | Automatic |
| Cache management | Automatic | Manual | Automatic |

### Migration Examples

**Makefile → build.zig**

```makefile
# Makefile
CC = gcc
CFLAGS = -std=c23 -Wall -O2
LDFLAGS = -lncurses

repo2mmd: main.o args.o
    $(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
    $(CC) $(CFLAGS) -c -o $@ $<
```

```zig
// build.zig equivalent
const exe = b.addExecutable(.{
    .name = "repo2mmd",
    .target = target,
    .optimize = .ReleaseSafe,
});
exe.addCSourceFiles(.{
    .files = &.{ "main.c", "args.c" },
    .flags = &.{ "-std=c23", "-Wall" },
});
exe.linkSystemLibrary("ncurses");
b.installArtifact(exe);
```

## Troubleshooting

### Common Issues

1. **"Unable to find zig"**
   ```bash
   # Install Zig from https://ziglang.org/download/
   # Or use the setup script:
   curl -sSf https://ziglang.org/download/index.json | jq -r '.master."x86_64-linux".tarball'
   ```

2. **"C header not found"**
   ```zig
   // Add include paths in build.zig
   exe.addIncludePath(b.path("include"));
   exe.addSystemIncludePath("/usr/local/include");
   ```

3. **"Undefined symbol"**
   ```zig
   // Ensure libraries are linked
   exe.linkSystemLibrary("m");  // math library
   exe.linkSystemLibrary("pthread");  // threading
   ```

4. **Cache issues**
   ```bash
   # Clear cache
   rm -rf zig-cache zig-out
   # Rebuild
   zig build
   ```

### Debug Build Issues

```bash
# Verbose build output
zig build --verbose

# Show compile commands
zig build --verbose-cc

# Keep temporary files
zig build --verbose-link
```

### Platform-Specific Issues

**Windows**
- Ensure Visual Studio Build Tools or MinGW is installed
- Use `zig cc` instead of `gcc` for better compatibility

**macOS**
- May need to install Xcode Command Line Tools
- Use `exe.linkFramework("CoreFoundation")` for system frameworks

**Linux**
- Install development packages: `apt install libncurses-dev`
- Check pkg-config: `pkg-config --libs ncurses`

## Advanced Topics

### Custom Build Steps

```zig
// Generate version header
const version_step = b.addSystemCommand(&.{
    "git", "describe", "--tags", "--always",
});
const version_header = version_step.captureStdOut();
exe.addCSourceFiles(.{
    .files = &.{"src/version.c"},
    .flags = &.{"-DVERSION=\"" ++ version_header ++ "\""},
});
```

### Conditional Compilation

```zig
// Feature flags
const enable_feature = b.option(bool, "feature", "Enable feature") orelse false;
if (enable_feature) {
    exe.defineCMacro("ENABLE_FEATURE", null);
    exe.addCSourceFile(.{
        .file = b.path("src/feature.c"),
        .flags = &.{"-std=c23"},
    });
}
```

### Testing C Code with Zig

```zig
// Create test executable
const test_exe = b.addExecutable(.{
    .name = "test_runner",
    .target = target,
});
test_exe.addCSourceFiles(.{
    .files = &.{
        "test/test_main.c",
        "test/test_utils.c",
    },
    .flags = &.{"-std=c23"},
});

const test_cmd = b.addRunArtifact(test_exe);
const test_step = b.step("test", "Run tests");
test_step.dependOn(&test_cmd.step);
```

## Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Build System Guide](https://ziglang.org/learn/build-system/)
- [Zig Discord](https://discord.gg/zig) - Active community for questions
- [This Project's build.zig](../build.zig) - Real example to study