# Repository Guidelines

## Project Structure & Module Organization
- `src/` hosts the Zig CLI: `main.zig` handles entry, with supporting modules for discovery, scheduling, diagnostics, and graph IR.
- `test/` mirrors runtime modules through focused specs (`test/cli_graph.zig`, `test/scheduler.zig`) and golden fixtures (`*manifest.zig`).
- `docs/` captures design references, `examples/` demonstrates CLI flows, `scripts/` holds `example.sh` (README example) and `release.sh` (release archives), and `zig-out/` can be regenerated.

## Kit MCP Usage for This Project

When working with code, ALWAYS:
1. Use Kit to open and analyze the codebase
2. Use Kit to explore the file structure
3. Use Kit to extract and analyze code symbols
4. Use Kit to research package documentation
5. Use Kit to build context before implementing

Available tools:
- Repository: open_repository, get_file_tree
- Analysis: extract_symbols, find_symbol_usages
- Search: search_text, get_dependency_graph
- Docs: deep_research_package

## Build, Test, and Development Commands
- `zig build` — debug build to `zig-out/bin/repo2mmd`.
- `zig build run -- --help` or `just run .` — invoke the CLI without installing.
- `zig build test` / `just test` — execute the suite in `test/main.zig`; add `-Doptimize=ReleaseSafe` for release coverage.
- `zig build fmt` / `just fmt` — format sources; `zig build fmt-check` enforces formatter parity with CI.
- `just check` — wrapper that runs `fmt-check` and tests before pushing.

### Using `zig build`
The `zig build` command is the primary way to build the project. It reads the `build.zig` file to understand the project structure and dependencies. Common usage patterns:

- **Basic build**: `zig build` - Compiles the project in debug mode
- **Release build**: `zig build -Doptimize=ReleaseFast` - Creates an optimized release build
- **Custom build steps**: `zig build <step>` - Run specific build steps defined in build.zig
- **Clean build**: `zig build clean` - Remove build artifacts

The build system automatically handles dependency management, cross-compilation, and caching of build artifacts.

## Naming rules (Zig casing, Tiger semantics)

**Casing**

* `lowerCamelCase` for functions, variables, fields, params, files that are general-purpose modules.
* `UpperCamelCase` for types, error sets, enum tags, and files whose primary export is a single type (`FooMap.zig`).
* Acronyms stay uppercase: `HTTPServer`, `VSRState`, variable `vsrState`, fn `parseHTTPHeaders`.

**Units and qualifiers**

* Word order = most-significant → least; unit last. Examples: `latencyMsMax`, `bytesTotal`, `retryCountLimit`.
* Prefer explicit units to type-based inference.

**Term choice**

* Pick precise domain nouns/verbs. Avoid overloaded words across concepts.
* No abbreviations except throwaway `i/j/n` in tight algorithm scopes.
* Prefer role names over generics: `gpa`, `arena`, `clock`, `journal`, `replica`.

**Pairs and alignment**

* Use `source` / `target` (not `src` / `dst`). Keep paired names parallel in length and structure.

**Helpers and callbacks**

* Prefix helpers with the caller/role when it improves grepability: `segmentRead`, `journalFlush`.
* Put callbacks last in param lists: `fn read(..., callback: *const Callback) void`.

**Parameters and options**

* Order params: context/deps → subject → configuration → callback.
* When two or more same-typed scalars would be ambiguous, use an `Options` struct.
* Name optionals so `null` reads clearly at call sites: `timeoutMs: ?u32 = null`, `cache: ?*Cache = null`.

**Files and modules**

* If a file's primary export is a type: `TypeName.zig`, top-level exposes that type.
* Otherwise: `snake_case.zig` for modules of functions/values.
* Inside a type: `const Self = @This();` → fields → nested types (only if simple) → methods. Lift complex nested types to their own files.

**CLI**

* Prefer long-form flags and explicit names. Single-letter flags only for interactive commands.

**Overloads and composition**

* Do not overload a term across layers. Compose names to read well in docs and code: `config.pipelineMax`, `replica.applyBatch()`.

**Migration guardrails**

* Follow Zig casing even in new code near older snake_case. Only rename existing identifiers when the change scope includes a repo-wide refactor.

---

### Examples

```zig
// Type file: VSRState.zig
pub const VSRState = struct {
    const Self = @This();

    gpa: *std.mem.Allocator,
    journal: *Journal,
    maxSegmentBytes: u64,
    retryCountLimit: u8,

    pub fn init(gpa: *std.mem.Allocator, journal: *Journal, opts: InitOptions) !Self { ... }

    pub fn applyBatch(self: *Self, entries: []const Entry, timeoutMs: ?u32) !void { ... }

    pub fn segmentRead(self: *Self, address: u64, sizeBytes: u32, callback: *const ReadCallback) void { ... }

    pub const InitOptions = struct {
        maxSegmentBytes: u64,
        retryCountLimit: u8 = 3,
        cache: ?*Cache = null,
        timeoutMs: ?u32 = null,
    };
};

// Module file: io_pipeline.zig
pub fn buildPipeline(gpa: *std.mem.Allocator, source: *Device, target: *Device) !Pipeline { ... }
pub fn latencyMsMax(samples: []const u32) u32 { ... }
```

**Agent rules**

* Enforce casing rules above for all new symbols.
* Add units to names, unit last.
* Use `Options` when you see ambiguous same-typed scalars.
* Keep callbacks last, preserve param order policy.
* Prefer `source/target`, avoid abbreviations, keep acronyms uppercase.
* Do not churn legacy snake_case unless performing an intentional rename pass.

## Coding Style & Naming Conventions
- Use Zig 0.15.1 exactly (pinned in `build.zig.zon`; `build.zig` rejects other versions) and always run `zig fmt`; the formatter locks indentation to four spaces and standard spacing.
- Keep modules snake_case; expose types in PascalCase and functions in lowerCamelCase; prefer explicit error sets to preserve CLI exit codes.
- Share helpers like `diag.printError` and scheduler primitives instead of redefining logging or traversal utilities.

## Testing Guidelines
- Place new specs under `test/` beside the module under test and import via `std.testing`.
- Expand CLI checks in `test/cli_graph.zig` and related manifest files whenever flags or surface behavior change.
- Maintain golden data (`test/manifest_golden.zig`, etc.) deterministically and review diffs to confirm intent.
- Validate with `zig build test -Doptimize=ReleaseSafe` before opening a review.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (`type(scope): summary`); recent history uses scopes such as `docs` and `scheduler`.
- Rebase branches on `main`, squash fixups, and keep subjects focused on user-visible impact.
- Pull requests should state intent, list touched modules, link issues, and attach CLI output or screenshots for UX updates.
- Require passing `zig build fmt-check` and `zig build test`; update `docs/` or `examples/` when contracts or workflows shift.

# Zig Cookbook

_Aggregated on October 7, 2025, from [zigcc/zig-cookbook](https://github.com/zigcc/zig-cookbook), MIT License, Copyright (c) the zig-cookbook contributors._

**Use these patterns throughout the codebase**

---

# Read file line by line

There is a [`Reader`] type in Zig, which provides various methods to read file, such as `readAll`, `readInt`. Here we will use `takeDelimiterExclusive` to split lines.

```zig
const std = @import("std");
const fs = std.fs;
const print = std.debug.print;

pub fn main() !void {
    const file = try fs.cwd().openFile("tests/zig-zen.txt", .{});
    defer file.close();

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(&file_buffer);
    var line_no: usize = 0;
    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        line_no += 1;
        print("{d}--{s}\n", .{ line_no, line });
    } else |err| switch (err) {
        error.EndOfStream => {}, // Normal termination
        else => return err, // Propagate error
    }

    print("Total lines: {d}\n", .{line_no});
}
```


[`reader`]: https://ziglang.org/documentation/0.14.0/std/#std.io.Reader

---

# Mmap file

Creates a memory map of a file using [mmap](https://man7.org/linux/man-pages/man2/mmap.2.html) and simulates some non-sequential reads from the file. Using a memory map means you just index into a slice rather than having to deal with seek to navigate a file.

```zig
const std = @import("std");
const fs = std.fs;
const print = std.debug.print;

const filename = "/tmp/zig-cookbook-01-02.txt";

pub fn main() !void {
    if (.windows == @import("builtin").os.tag) {
        std.debug.print("MMap is not supported in Windows\n", .{});
        return;
    }

    const file = try fs.cwd().createFile(filename, .{
        .read = true,
        .truncate = true,
        .exclusive = false, // Set to true will ensure this file is created by us
    });
    defer file.close();
    const content_to_write = "hello zig cookbook";

    // Before mmap, we need to ensure file isn't empty
    try file.setEndPos(content_to_write.len);

    const md = try file.stat();
    try std.testing.expectEqual(md.size, content_to_write.len);

    const ptr = try std.posix.mmap(
        null,
        content_to_write.len,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        file.handle,
        0,
    );
    defer std.posix.munmap(ptr);

    // Write file via mmap
    std.mem.copyForwards(u8, ptr, content_to_write);

    // Read file via mmap
    try std.testing.expectEqualStrings(content_to_write, ptr);
}
```

---

# Find files that have been modified in the last 24 hours

Gets the current working directory by calling `fs.cwd()`, and then iterates files using `walk()`, which will recursively iterate entries in the directory.

For each entry, we check if it's a file, and use `statFile()` to retrieve the file's metadata.

```zig
//! Find files that have been modified in the last 24 hours

const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var iter_dir = try fs.cwd().openDir("src", .{ .iterate = true });
    defer iter_dir.close();

    var walker = try iter_dir.walk(allocator);
    defer walker.deinit();

    const now = std.time.nanoTimestamp();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        const stat = try iter_dir.statFile(entry.path);
        const last_modified = stat.mtime;
        const duration = now - last_modified;
        if (duration < std.time.ns_per_hour * 24) {
            print("Last modified: {d} seconds ago, size:{d} bytes, filename: {s}\n", .{
                @divTrunc(duration, std.time.ns_per_s),
                stat.size,
                entry.path,
            });
        }
    }
}
```

---

# Check file existence

In this example, `access` is utilized to verify file existence; however, for it to function correctly, one must specifically check for the `FileNotFound` error type.

```zig
//! Test file/directory existence

const std = @import("std");
const fs = std.fs;

pub fn main() !void {
    const filename = "build.zig";
    var found = true;
    fs.cwd().access(filename, .{}) catch |e| switch (e) {
        error.FileNotFound => found = false,
        else => return e,
    };

    std.debug.assert(found);
}
```


However, there is a gotcha described in [its documentation](https://github.com/ziglang/zig/blob/0.13.0/lib/std/fs/Dir.zig#L2390-L2396):

> Be careful of [Time-Of-Check-Time-Of-Use](https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use) race conditions when using this function.
> For example, instead of testing if a file exists and then opening it, just open it and handle the error for file not found.

---

# Iterate directory

Iterate directory

There is a convenient method `walk` for this purpose, it will walk the directory iteratively.

```zig
const std = @import("std");
const fs = std.fs;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("leak");
    const allocator = gpa.allocator();

    // In order to walk the directry, `iterate` must be set to true.
    var dir = try fs.cwd().openDir("zig-out", .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        print("path: {s}, basename:{s}, type:{s}\n", .{
            entry.path,
            entry.basename,
            @tagName(entry.kind),
        });
    }
}
```


The order of returned file system entries is undefined, if there are any requirements for the order in which to return the entries, such as alphabetical or chronological, sort them accordingly. Otherwise, leave them in their original, unsorted order.

---

# Calculate SHA-256 digest of a file

Calculate SHA-256 digest of a file

There are many crypto algorithm implementations in std, `sha256`, `md5` are supported out of box.

```zig
const std = @import("std");
const fs = std.fs;
const Sha256 = std.crypto.hash.sha2.Sha256;

// In real world, this may set to page_size, usually it's 4096.
const BUF_SIZE = 16;

fn sha256_digest(
    file: fs.File,
) ![Sha256.digest_length]u8 {
    var sha256 = Sha256.init(.{});
    var file_buf: [BUF_SIZE]u8 = undefined;
    var reader = file.reader(&file_buf);
    var read_buf: [BUF_SIZE]u8 = undefined;
    var n = try reader.interface.readSliceShort(&read_buf);
    while (n != 0) {
        sha256.update(read_buf[0..n]);
        n = try reader.interface.readSliceShort(&read_buf);
    }

    return sha256.finalResult();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file = try fs.cwd().openFile("tests/zig-zen.txt", .{});
    defer file.close();

    const digest = try sha256_digest(file);
    const hex_digest = try std.fmt.allocPrint(
        allocator,
        "{x}",
        .{&digest},
    );
    defer allocator.free(hex_digest);

    try std.testing.expectEqualStrings(
        "2210e9263ece534df0beff39ec06850d127dc60aa17bbc7769c5dc2ea5f3e342",
        hex_digest,
    );
}
```

---

# Salt and hash a password with PBKDF2

Salt and hash a password with PBKDF2

Uses [`std.crypto.pwhash.pbkdf2`] to hash a salted password. The salt is generated
using [`std.rand.DefaultPrng`], which fills the salt byte array with generated
random numbers.

```zig
const std = @import("std");
const print = std.debug.print;
const crypto = std.crypto;
const HmacSha256 = crypto.auth.hmac.sha2.HmacSha256;

pub fn main() !void {
    const salt = [_]u8{ 'a', 'b', 'c' };
    const password = "Guess Me If You Can!";
    const rounds = 1_000;

    // Usually 16 or 32 bytes
    var derived_key: [16]u8 = undefined;
    try crypto.pwhash.pbkdf2(&derived_key, password, &salt, rounds, HmacSha256);

    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{
            44,
            184,
            223,
            181,
            238,
            128,
            211,
            50,
            149,
            114,
            26,
            86,
            225,
            172,
            116,
            81,
        },
        &derived_key,
    );
}
```


[`std.crypto.pwhash.pbkdf2`]: https://ziglang.org/documentation/0.11.0/std/#A;std:crypto.pwhash.pbkdf2
[`std.rand.defaultprng`]: https://ziglang.org/documentation/0.11.0/std/#A;std:rand.DefaultPrng

---

# Salt and hash a password with Argon2

Salt and hash a password with Argon2

This Zig program derives a cryptographic key from a password and salt using the Argon2id password hashing algorithm. It uses [std.crypto.pwhash.argon2] to hash a salted password, where the salt is generated using [`std.crypto.random`].

```zig
const std = @import("std");

pub fn main() !void {
    var dbg = std.heap.DebugAllocator(.{}){};
    defer _ = dbg.deinit();
    const allocator = dbg.allocator();

    const password = "happy";

    //Random salt (Must be at least 8 bytes, recommended 16+)
    var raw: [8]u8 = undefined;
    std.crypto.random.bytes(&raw);
    const salt = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(raw, .lower)});
    defer allocator.free(salt);

    //Parameters for Argon2id
    const params = std.crypto.pwhash.argon2.Params{
        .t = 3, // Iterations (time cost)
        .m = 16, // Memory cost in KiB (here 16 MiB)
        .p = 1, // Threads
    };

    const dk_len: usize = 16; // derive 16 or 32-byte key
    var derived: [dk_len]u8 = undefined;

    try std.crypto.pwhash.argon2.kdf(
        allocator,
        &derived,
        password,
        salt,
        params,
        .argon2id, //argon2i, argon2d and argon2id
    );

    std.debug.print("Argon2id derived key: {s}\n", .{std.fmt.bytesToHex(derived, .lower)});
}
```


[`std.crypto.pwhash.argon2`]: https://ziglang.org/documentation/0.14.0/std/#std.crypto.pwhash.argon2
[`std.crypto.random`]: https://ziglang.org/documentation/0.14.0/std/#std.crypto.tlcsprng.interface

---

# Measure the elapsed time between two code sections

[`Instant`] represents a timestamp with respect to the currently executing program that ticks while the program is suspended and can be used to record elapsed time.

Calling [`std.time.Instant.since`] returns a u64 representing nanoseconds elapsed.

This is such a common task, that there is a [`Timer`] for convenience.

```zig
const std = @import("std");
const time = std.time;
const Instant = time.Instant;
const Timer = time.Timer;
const print = std.debug.print;

fn expensive_function() void {
    // sleep 500ms
    std.Thread.sleep(time.ns_per_ms * 500);
}

pub fn main() !void {
    // Method 1: Instant
    const start = try Instant.now();
    expensive_function();
    const end = try Instant.now();
    const elapsed1: f64 = @floatFromInt(end.since(start));
    print("Time elapsed is: {d:.3}ms\n", .{
        elapsed1 / time.ns_per_ms,
    });

    // Method 2: Timer
    var timer = try Timer.start();
    expensive_function();
    const elapsed2: f64 = @floatFromInt(timer.read());
    print("Time elapsed is: {d:.3}ms\n", .{
        elapsed2 / time.ns_per_ms,
    });
}
```


[`instant`]: https://ziglang.org/documentation/0.11.0/std/#A;std:time.Instant
[`timer`]: https://ziglang.org/documentation/0.11.0/std/#A;std:time.Timer
[`std.time.instant.since`]: https://ziglang.org/documentation/0.11.0/std/#A;std:time.Instant.since

---

# Listen on unused port TCP/IP

In this example, the port is displayed on the console, and the program will
listen until a request is made. `Ip4Address` assigns a random port when
setting port to 0.

```zig
//! Start an echo TCP server at an unused port.
//!
//! Test with
//! echo "hello zig" | nc localhost <port>

const std = @import("std");
const net = std.net;
const print = std.debug.print;

pub fn main() !void {
    const loopback = try net.Ip4Address.parse("127.0.0.1", 0);
    const localhost = net.Address{ .in = loopback };
    var server = try localhost.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    const addr = server.listen_address;
    print("Listening on {}, access this port to end the program\n", .{addr.getPort()});

    const client = try server.accept();
    // In real world, you'd want to handle multiple clients, probably in separate threads.
    try handleClient(client);
}

fn handleClient(client: net.Server.Connection) !void {
    print("Accepted connection from {f}\n", .{client.address});
    defer client.stream.close();
    var stream_buf: [1024]u8 = undefined;
    var reader = client.stream.reader(&stream_buf);
    // Here we echo back what we read directly, so the writer buffer is empty
    var writer = client.stream.writer(&.{});

    while (true) {
        print("Waiting for data from {f}...\n", .{client.address});
        const msg = reader.interface().takeDelimiterInclusive('\n') catch |err| {
            if (err == error.EndOfStream) {
                print("{f} closed the connection\n", .{client.address});
                return;
            } else {
                return err;
            }
        };
        print("{f} says {s}", .{ client.address, msg });
        try writer.interface.writeAll(msg);
        // No need to flush, as writer buffer is empty
    }
}
```


When start starts up, try test like this:

```bash
echo "hello zig" | nc localhost <port>
```

By default, the program listens with IPv4. If you want IPv6, use `::1`
instead of `127.0.0.1`, replace `net.Ip4Address.parse` by
`net.Ip6Address.parse` and the field `.in` in the creation of the
`net.Address` with `.in6`.

(And connect to something like `ip6-localhost`, depending on the way
your machine is set up.)

The next section will show how to connect to this server using Zig code.

---

# TCP Client

In this example, we demonstrate creation of a TCP client to connect to the server from the previous section.
You can run it using `zig build run-04-02 -- <port>`.

```zig
const std = @import("std");
const net = std.net;
const print = std.debug.print;

pub fn main() !void {
    var args = std.process.args();
    // The first (0 index) Argument is the path to the program.
    _ = args.skip();
    const port_value = args.next() orelse {
        print("expect port as command line argument\n", .{});
        return error.NoPort;
    };
    const port = try std.fmt.parseInt(u16, port_value, 10);

    const peer = try net.Address.parseIp4("127.0.0.1", port);
    // Connect to peer
    const stream = try net.tcpConnectToAddress(peer);
    defer stream.close();
    print("Connecting to {f}\n", .{peer});

    // Sending data to peer
    const data = "hello zig";
    var buffer: [1024]u8 = undefined;
    var writer = stream.writer(buffer[0..]);
    try writer.interface.writeAll(data);
    try writer.interface.flush();
    print("Sending '{s}' to peer, total written: {d} bytes\n", .{ data, data.len });
}
```


By default, the program connects with IPv4. If you want IPv6, use
`::1` instead of `127.0.0.1`, replace `net.Address.parseIp4` by
`net.Address.parseIp6`.

---

# UDP Echo

Similar to the TCP server example, this program will listen on the specified
IP address and port, but for UDP datagrams this time. If data is received,
it will be echoed back to the sender's address.

Although `std.net` is mostly focused on abstractions for TCP (so far), we can still
make use of socket programming to communicate via UDP.

```zig
//! Start a UDP echo on an unused port.
//!
//! Test with
//! echo "hello zig" | nc -u localhost <port>

const std = @import("std");
const net = std.net;
const posix = std.posix;
const print = std.debug.print;

pub fn main() !void {
    // adjust the ip/port here as needed
    const addr = try net.Address.parseIp("127.0.0.1", 32100);

    // get a socket and set domain, type and protocol flags
    const sock = try posix.socket(
        posix.AF.INET,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );

    // for completeness, we defer closing the socket. In practice, if this is
    // a one-shot program, we could omit this and let the OS do the cleanup
    defer posix.close(sock);

    try posix.bind(sock, &addr.any, addr.getOsSockLen());

    var other_addr: posix.sockaddr = undefined;
    var other_addrlen: posix.socklen_t = @sizeOf(posix.sockaddr);

    var buf: [1024]u8 = undefined;

    print("Listen on {f}\n", .{addr});

    // we did not set the NONBLOCK flag (socket type flag),
    // so the program will wait until data is received
    const n_recv = try posix.recvfrom(
        sock,
        buf[0..],
        0,
        &other_addr,
        &other_addrlen,
    );
    print(
        "received {d} byte(s) from {any};\n    string: {s}\n",
        .{ n_recv, other_addr, buf[0..n_recv] },
    );

    // we could extract the source address of the received data by
    // parsing the other_addr.data field

    const n_sent = try posix.sendto(
        sock,
        buf[0..n_recv],
        0,
        &other_addr,
        other_addrlen,
    );
    print("echoed {d} byte(s) back\n", .{n_sent});
}
```


After starting the program, test as follows with `nc`, using the `-u` flag for UDP:

```bash
echo "hello zig" | nc -u localhost <port>
```

---

# GET

Parses the supplied URL and makes a synchronous HTTP GET request
with [`request`]. Prints obtained [`Response`] status and headers.

> Note: Since HTTP support is in early stage, it's recommended to use [libcurl](https://curl.se/libcurl/c/) for any complex task.
> And when the buffer is not enough, it will return `error.HttpHeadersOverSize`

```zig
const std = @import("std");
const print = std.debug.print;
const http = std.http;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse("http://httpbin.org/headers");
    const buf = try allocator.alloc(u8, 1024 * 8);
    defer allocator.free(buf);
    var req = try client.request(.GET, uri, .{
        .extra_headers = &.{.{ .name = "Custom-header", .value = "Custom Value" }},
    });
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buffer: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);
    var iter = response.head.iterateHeaders();
    while (iter.next()) |header| {
        std.debug.print("Name:{s}, Value:{s}\n", .{ header.name, header.value });
    }

    try std.testing.expectEqual(response.head.status, .ok);
    const body = try response.reader(&.{}).allocRemaining(allocator, .unlimited);
    defer allocator.free(body);

    print("Body:\n{s}\n", .{body});
}
```


[`request`]: https://ziglang.org/documentation/0.11.0/std/src/std/http/Client.zig.html#L992
[`response`]: https://ziglang.org/documentation/0.11.0/std/src/std/http/Client.zig.html#L322

---

# POST

Parses the supplied URL and makes a synchronous HTTP POST request
with [`request`]. Prints obtained [`Response`] status, and data received from server.

> Note: Since HTTP support is in early stage, it's recommended to use [libcurl](https://curl.se/libcurl/c/) for any complex task.

```zig
const std = @import("std");
const print = std.debug.print;
const http = std.http;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse("https://httpbin.org/anything");

    var req = try client.request(.POST, uri, .{
        .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
    });
    defer req.deinit();

    var payload: [7]u8 = "[1,2,3]".*;
    try req.sendBodyComplete(&payload);
    var buf: [1024]u8 = undefined;
    var response = try req.receiveHead(&buf);

    // Occasionally, httpbin might time out, so we disregard cases
    // where the response status is not okay.
    if (response.head.status != .ok) {
        return;
    }

    const body = try response.reader(&.{}).allocRemaining(allocator, .unlimited);
    defer allocator.free(body);
    print("Body:\n{s}\n", .{body});
}
```


[`request`]: https://ziglang.org/documentation/0.11.0/std/src/std/http/Client.zig.html#L992
[`response`]: https://ziglang.org/documentation/0.11.0/std/src/std/http/Client.zig.html#L322

---

# http.Server - std

A basic implementation of `http.Server` has been introduced since Zig 0.12.0.

For each connection we spawn a new thread to handle it, in `accept` it will:
1. First it use `defer` to ensure the connection is closed when returned.
2. Then init a HTTP server to begin parse request
3. For each request, we first check if it could upgrade to WebSocket.
   - If it succeeds, call `serveWebSocket` else call `serverHTTP`

```zig
const std = @import("std");
const log = std.log;
const Request = std.http.Server.Request;
const Connection = std.net.Server.Connection;

const MAX_BUF = 1024;

pub fn main() !void {
    const addr = try std.net.Address.parseIp("127.0.0.1", 8080);
    var server = try std.net.Address.listen(addr, .{ .reuse_address = true });
    defer server.deinit();

    log.info("Start HTTP server at {f}", .{addr});

    while (true) {
        const conn = server.accept() catch |err| {
            log.err("failed to accept connection: {s}", .{@errorName(err)});
            continue;
        };
        _ = std.Thread.spawn(.{}, accept, .{conn}) catch |err| {
            log.err("unable to spawn connection thread: {s}", .{@errorName(err)});
            conn.stream.close();
            continue;
        };
    }
}

fn accept(conn: Connection) !void {
    defer conn.stream.close();

    log.info("Got new client({f})!", .{conn.address});

    var recv_buffer: [1024]u8 = undefined;
    var send_buffer: [100]u8 = undefined;
    var connection_br = conn.stream.reader(&recv_buffer);
    var connection_bw = conn.stream.writer(&send_buffer);
    var server = std.http.Server.init(connection_br.interface(), &connection_bw.interface);
    while (server.reader.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return err,
        };

        switch (request.upgradeRequested()) {
            .other => |other_protocol| {
                log.err("Not supported protocol, {s}", .{other_protocol});
                return;
            },
            .websocket => |key| {
                var ws = try request.respondWebSocket(.{ .key = key orelse "" });
                try serveWebSocket(&ws);
            },
            .none => {
                try serveHTTP(&request);
            },
        }
    }
}

fn serveHTTP(request: *Request) !void {
    try request.respond(
        "Hello World from Zig HTTP server",
        .{
            .extra_headers = &.{
                .{ .name = "custom-header", .value = "custom value" },
            },
        },
    );
}

fn serveWebSocket(ws: *std.http.Server.WebSocket) !void {
    try ws.writeMessage("Hello from Zig WebSocket server", .text);
    while (true) {
        const msg = try ws.readSmallMessage();
        if (msg.opcode == .connection_close) {
            log.info("Client closed the WebSocket", .{});
            return;
        }
        try ws.writeMessage(msg.data, msg.opcode);
    }
}
```


## Test

For HTTP, we could use `curl`:
```bash
curl -v localhost:8080
```
It will output:
```bash
< HTTP/1.1 200 OK
< content-length: 32
< custom header: custom value
<
Hello World from Zig HTTP server
```

For WebSocket, we could use console in your browser's `Developer Tools`:

```js
var webSocket = new WebSocket('ws://localhost:8080');
webSocket.onmessage = function(data) { console.log(data); }
```
Then we could send message like this:
```js
webSocket.send('abc')
```

![websocket-client](https://cookbook.ziglang.cc/images/websocket-client.webp)

See [Writing WebSocket client applications - Web APIs | MDN](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_client_applications) for details.

## Note
The std implementation exhibits extremely poor performance. If you're planning beyond basic experimentation, consider utilizing alternative libraries such as:
- <https://github.com/karlseguin/http.zig>
- <https://github.com/zigzap/zap>
- <https://github.com/mookums/zzz>

---

# Generate random numbers

Generates random numbers with the help of a thread-local, cryptographically secure pseudo random number generator [`std.crypto.random`].

```zig
const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    const rand = std.crypto.random;

    print("Random u8: {}\n", .{rand.int(u8)});
    print("Random u8 less than 10: {}\n", .{rand.uintLessThan(u8, 10)});
    print("Random u16: {}\n", .{rand.int(u16)});
    print("Random u32: {}\n", .{rand.int(u32)});
    print("Random i32: {}\n", .{rand.int(i32)});
    print("Random float: {d}\n", .{rand.float(f64)});

    var i: usize = 0;
    while (i < 9) {
        print("Random enum: {}\n", .{rand.enumValue(enum { red, green, blue })});
        i += 1;
    }
}
```


[`std.crypto.random`]: https://ziglang.org/documentation/0.11.0/std/#A;std:crypto.random

---

# Spawn a short-lived thread

The example uses [`std.Thread`] for concurrent and parallel programming.
[`std.Thread.spawn`] spawns a new thread to calculate the result.

This example splits the array in half and performs the work in separate threads.

> Note: In order to ensure `t1` thread is completed when spawn `t2` fails, we `defer t1.join()` immediately after spawn `t1`.

```zig
const std = @import("std");

pub fn main() !void {
    var arr = [_]i32{ 1, 25, -4, 10, 100, 200, -100, -200 };
    var max_value: i32 = undefined;
    try findMax(&max_value, &arr);
    try std.testing.expectEqual(max_value, 200);
}

fn findMax(max_value: *i32, values: []i32) !void {
    const THRESHOLD: usize = 2;

    if (values.len <= THRESHOLD) {
        var res = values[0];
        for (values) |it| {
            res = @max(res, it);
        }
        max_value.* = res;
        return;
    }

    const mid = values.len / 2;
    const left = values[0..mid];
    const right = values[mid..];

    var left_max: i32 = undefined;
    var right_max: i32 = undefined;
    // This block is necessary to ensure that all threads are joined before proceeding.
    {
        const t1 = try std.Thread.spawn(.{}, findMax, .{ &left_max, left });
        defer t1.join();
        const t2 = try std.Thread.spawn(.{}, findMax, .{ &right_max, right });
        defer t2.join();
    }

    max_value.* = @max(left_max, right_max);
}
```


[`std.thread`]: https://ziglang.org/documentation/0.11.0/std/#A;std:Thread
[`std.thread.spawn`]: https://ziglang.org/documentation/0.11.0/std/#A;std:Thread.spawn

---

# Share data between two threads

When we want to mutate data shared between threads, [`Mutex`](https://ziglang.org/documentation/0.11.0/std/#A;std:Thread.Mutex)(**Mut**ually **ex**clusive flag) must be used to synchronize threads, otherwise the result maybe unexpected.

```zig
const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const SharedData = struct {
    mutex: Mutex,
    value: i32,

    pub fn updateValue(self: *SharedData, increment: i32) void {
        // Use `tryLock` if you don't want to block
        self.mutex.lock();
        defer self.mutex.unlock();

        for (0..10000) |_| {
            self.value += increment;
        }
    }
};

pub fn main() !void {
    var shared_data = SharedData{ .mutex = Mutex{}, .value = 0 };
    // This block is necessary to ensure that all threads are joined before proceeding.
    {
        const t1 = try Thread.spawn(.{}, SharedData.updateValue, .{ &shared_data, 1 });
        defer t1.join();
        const t2 = try Thread.spawn(.{}, SharedData.updateValue, .{ &shared_data, 2 });
        defer t2.join();
    }
    try std.testing.expectEqual(shared_data.value, 30_000);
}
```

If we remove Mutex protection, the result will most like be less than 30,000.

[`Mutex`]: https://ziglang.org/documentation/0.11.0/std/#A;std:Thread.Mutex

---

# Thread pool

Thread pools address two different problems:
1. They usually provide improved performance when executing large numbers of asynchronous tasks, due to reduced per-task invocation overhead, and
2. They provide a means of bounding and managing the resources, including threads, consumed when executing a collection of tasks.


In this example, we spawn 10 tasks into thread pool, and use `WaitGroup` to wait for them to finish.

```zig
const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("leak");
    const allocator = gpa.allocator();

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = 4,
    });
    defer pool.deinit();

    var wg: std.Thread.WaitGroup = .{};
    for (0..10) |i| {
        pool.spawnWg(&wg, struct {
            fn run(id: usize) void {
                print("I'm from {d}\n", .{id});
            }
        }.run, .{i});
    }
    wg.wait();

    print("All threads exit.\n", .{});
}
```

---

# Run Once

`std.once` ensures a function executes exactly one time, regardless of how many threads attempt to call it or how many times it's invoked. This thread-safe initialization is particularly useful for singleton patterns and one-time setup operations.

```zig
const std = @import("std");

var n: u8 = 0;

fn incr() void {
    n = n + 1;
}

var once_incr = std.once(incr);

fn onceIncr() void {
    // The invocations of `call` are thread-safe.
    once_incr.call();
    once_incr.call();
}

pub fn main() !void {
    {
        const t1 = try std.Thread.spawn(.{}, onceIncr, .{});
        defer t1.join();
        const t2 = try std.Thread.spawn(.{}, onceIncr, .{});
        defer t2.join();
    }

    try std.testing.expectEqual(1, n);
}
```

---

# Check number of logical cpu cores

Shows the number of logical CPU cores in the current machine using [`std.Thread.getCpuCount`].

```zig
const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    print("Number of logical cores is {}\n", .{try std.Thread.getCpuCount()});
}
```


[`std.thread.getcpucount`]: https://ziglang.org/documentation/0.11.0/std/#A;std:Thread.getCpuCount

---

# External Command

Run an external command via [`std.process.Child`], and collect output into `ArrayList` via [pipe].

```zig
const std = @import("std");
const print = std.debug.print;
const Child = std.process.Child;
const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("leak");
    const allocator = gpa.allocator();

    const argv = [_][]const u8{
        "echo",
        "-n",
        "hello",
        "world",
    };

    // By default, child will inherit stdout & stderr from its parents,
    // this usually means that child's output will be printed to terminal.
    // Here we change them to pipe and collect into `ArrayList`.
    var child = Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout: std.ArrayListUnmanaged(u8) = .empty;
    defer stdout.deinit(allocator);
    var stderr: std.ArrayListUnmanaged(u8) = .empty;
    defer stderr.deinit(allocator);

    try child.spawn();
    try child.collectOutput(allocator, &stdout, &stderr, 1024);
    const term = try child.wait();

    try std.testing.expectEqual(term.Exited, 0);
    try std.testing.expectEqualStrings("hello world", stdout.items);
    try std.testing.expectEqualStrings("", stderr.items);
}
```


[`std.process.child`]: https://ziglang.org/documentation/0.11.0/std/#A;std:process.Child
[pipe]: https://man7.org/linux/man-pages/man2/pipe.2.html

---

# Parse a version string.

Constructs a [`std.SemanticVersion`] from a string literal using [`SemanticVersion.parse`].

```zig
const std = @import("std");
const assert = std.debug.assert;

pub fn main() !void {
    const version = try std.SemanticVersion.parse("0.2.6");

    assert(version.order(.{
        .major = 0,
        .minor = 2,
        .patch = 6,
        .pre = null,
        .build = null,
    }) == .eq);
}
```


[`std.semanticversion`]: https://ziglang.org/documentation/0.11.0/std/#A;std:SemanticVersion
[`semanticversion.parse`]: https://ziglang.org/documentation/0.11.0/std/#A;std:SemanticVersion.parse
[semantic versioning specification]: http://semver.org/

---

# Serialize and deserialize JSON

The [`std.json`] provides a set of functions such as [`stringify`] and [`stringifyAlloc`] for serializing JSON.
Additionally, we can use [`parseFromSlice`] function to parse a `[]u8` of JSON.

The example below shows a `[]u8` of JSON being parsed. Compare each member one by one.
Then, we modify the `verified` field to `false` and serialize it back into a JSON string.

```zig
const std = @import("std");
const json = std.json;
const testing = std.testing;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Deserialize JSON
    const json_str =
        \\{
        \\  "userid": 103609,
        \\  "verified": true,
        \\  "access_privileges": [
        \\    "user",
        \\    "admin"
        \\  ]
        \\}
    ;
    const T = struct { userid: i32, verified: bool, access_privileges: [][]u8 };
    const parsed = try json.parseFromSlice(T, allocator, json_str, .{});
    defer parsed.deinit();

    var value = parsed.value;

    try testing.expect(value.userid == 103609);
    try testing.expect(value.verified);
    try testing.expectEqualStrings("user", value.access_privileges[0]);
    try testing.expectEqualStrings("admin", value.access_privileges[1]);

    // Serialize JSON
    value.verified = false;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var stringifier = json.Stringify{
        .writer = &out.writer,
        .options = .{
            .whitespace = .indent_2,
        },
    };
    try stringifier.write(value);

    try testing.expectEqualStrings(
        \\{
        \\  "userid": 103609,
        \\  "verified": false,
        \\  "access_privileges": [
        \\    "user",
        \\    "admin"
        \\  ]
        \\}
    , out.writer.buffered());
}
```


[`std.json`]: https://ziglang.org/documentation/0.11.0/std/#A;std:json
[`stringify`]: https://ziglang.org/documentation/0.11.0/std/#A;std:json.stringify
[`stringifyalloc`]: https://ziglang.org/documentation/0.11.0/std/#A;std:json.stringifyAlloc
[`parsefromslice`]: https://ziglang.org/documentation/0.11.0/std/#A;std:json.parseFromSlice

---

# Serialize and deserialize Zon

ZON ("Zig Object Notation") is a textual file format. Outside of `nan` and `inf` literals, ZON's grammar is a subset of Zig's.

Supported Zig primitives:
* boolean literals
* number literals (including `nan` and `inf`)
* character literals
* enum literals
* `null` literals
* string literals
* multiline string literals

 Supported Zig container types:
 * anonymous struct literals
 * anonymous tuple literals

```zig
const std = @import("std");
const zon = std.zon;
const Allocator = std.mem.Allocator;

const Student = struct {
    name: []const u8,
    age: u16,
    favourites: []const []const u8,

    fn deinit(self: *Student, allocator: Allocator) void {
        allocator.free(self.name);
        for (self.favourites) |item| {
            allocator.free(item);
        }
        allocator.free(self.favourites);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("leak");
    const allocator = gpa.allocator();

    const source = Student{
        .name = "John",
        .age = 20,
        .favourites = &.{ "swimming", "running" },
    };

    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    try zon.stringify.serialize(source, .{}, &writer.writer);

    const expected =
        \\.{
        \\    .name = "John",
        \\    .age = 20,
        \\    .favourites = .{ "swimming", "running" },
        \\}
    ;
    const actual = writer.writer.buffered();
    try std.testing.expectEqualStrings(expected, actual);

    // Make it 0-sentinel
    try writer.writer.writeByte(0);
    const buffer = writer.writer.buffered();
    const input = buffer[0 .. buffer.len - 1 :0];

    var diag: zon.parse.Diagnostics = .{};
    defer diag.deinit(allocator);
    var parsed = zon.parse.fromSlice(
        Student,
        allocator,
        input,
        &diag,
        .{ .free_on_error = true },
    ) catch |err| {
        std.debug.print("Parse status: {any}\n", .{diag});
        return err;
    };
    defer parsed.deinit(allocator);

    try std.testing.expectEqualDeep(source, parsed);
}
```

---

# Encode and decode base64

Encodes a byte slice into `base64` string using [`std.base64.standard`] [`encode`]
and decodes it with [`standard`] [`decode`].

```zig
const std = @import("std");
const zon = std.zon;
const Allocator = std.mem.Allocator;

const Student = struct {
    name: []const u8,
    age: u16,
    favourites: []const []const u8,

    fn deinit(self: *Student, allocator: Allocator) void {
        allocator.free(self.name);
        for (self.favourites) |item| {
            allocator.free(item);
        }
        allocator.free(self.favourites);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("leak");
    const allocator = gpa.allocator();

    const source = Student{
        .name = "John",
        .age = 20,
        .favourites = &.{ "swimming", "running" },
    };

    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    try zon.stringify.serialize(source, .{}, &writer.writer);

    const expected =
        \\.{
        \\    .name = "John",
        \\    .age = 20,
        \\    .favourites = .{ "swimming", "running" },
        \\}
    ;
    const actual = writer.writer.buffered();
    try std.testing.expectEqualStrings(expected, actual);

    // Make it 0-sentinel
    try writer.writer.writeByte(0);
    const buffer = writer.writer.buffered();
    const input = buffer[0 .. buffer.len - 1 :0];

    var diag: zon.parse.Diagnostics = .{};
    defer diag.deinit(allocator);
    var parsed = zon.parse.fromSlice(
        Student,
        allocator,
        input,
        &diag,
        .{ .free_on_error = true },
    ) catch |err| {
        std.debug.print("Parse status: {any}\n", .{diag});
        return err;
    };
    defer parsed.deinit(allocator);

    try std.testing.expectEqualDeep(source, parsed);
}
```


[`std.base64.standard`]: https://ziglang.org/documentation/0.11.0/std/#A;std:base64.standard
[`standard`]: https://ziglang.org/documentation/0.11.0/std/src/std/base64.zig.html#L29
[`encode`]: https://ziglang.org/documentation/0.11.0/std/#A;std:base64.Base64Encoder.encode
[`decode`]: https://ziglang.org/documentation/0.11.0/std/#A;std:base64.Base64Decoder.decode

---

# Creating and adding complex numbers

Creates complex numbers of type [`std.math.Complex`]. Both the real and
imaginary part of the complex number must be of the same type.

Performing mathematical operations on complex numbers is the same as on
built in types: the numbers in question must be of the same type (i.e. floats
or integers).

```zig
const std = @import("std");
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const Complex = std.math.Complex;

pub fn main() !void {
    const complex_integer = Complex(i32).init(10, 20);
    const complex_integer2 = Complex(i32).init(5, 17);
    const complex_float = Complex(f32).init(10.1, 20.1);

    print("Complex integer: {}\n", .{complex_integer});
    print("Complex float: {}\n", .{complex_float});

    const sum = complex_integer.add(complex_integer2);

    try expectEqual(sum, Complex(i32).init(15, 37));
}
```


[`std.math.complex`]: https://ziglang.org/documentation/0.11.0/std/#A;std:math.Complex

---

# Bitfield

The fields of a [packed struct](https://ziglang.org/documentation/master/#packed-struct) are always laid out in memory in the order they are written, with no padding, so they are very nice to represent a bitfield.

Boolean values are represented as 1 bit in a packed struct, Zig also has arbitrary bit-width integers, like u28, u1 and so on.

```zig
const std = @import("std");
const print = std.debug.print;

const ColorFlags = packed struct(u32) {
    red: bool = false,
    green: bool = false,
    blue: bool = false,

    _padding: u29 = 0,
};

pub fn main() !void {
    const tom: ColorFlags = @bitCast(@as(u32, 0xFF));

    if (tom.red) {
        print("Tom likes red.\n", .{});
    }

    if (tom.red and tom.green) {
        print("Tom likes red and green.\n", .{});
    }

    const jerry: ColorFlags = @bitCast(@as(u32, 0x01));

    if (jerry.red) {
        print("Jerry likes red.\n", .{});
    }

    if (jerry.red and !jerry.green) {
        print("Jerry likes red, not green.\n", .{});
    }
}
```


## Reference

- [Packed structs in Zig make bit/flag sets trivial | Hexops' devlog](https://devlog.hexops.com/2022/packed-structs-in-zig/)
- [A Better Way to Implement Bit Fields](https://andrewkelley.me/post/a-better-way-to-implement-bit-fields.html)

---

# Singly Linked List

[Singly linked list] contains nodes linked together. The list contains:
- `head`, head of the list, used for traversal.
- `tail`, tail of the list, used for fast add.
- `len`, length of the list

Operations that can be performed on singly linked lists include:
- Insertion O(1)
- Deletion O(n), which is the most complex since it needs to maintain head/tail pointer.
- Traversal O(n)

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

fn LinkedList(comptime T: type) type {
    return struct {
        const Node = struct {
            data: T,
            next: ?*Node = null,
        };
        const Self = @This();

        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize = 0,
        allocator: Allocator,

        fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        fn add(self: *Self, value: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = value };

            if (self.tail) |*tail| {
                tail.*.next = node;
                tail.* = node;
            } else {
                self.head = node;
                self.tail = node;
            }

            self.len += 1;
        }

        fn remove(self: *Self, value: T) bool {
            if (self.head == null) {
                return false;
            }

            // In this loop, we are trying to find the node that contains the value.
            // We need to keep track of the previous node to update the tail pointer if necessary.
            var current = self.head;
            var previous: ?*Node = null;
            while (current) |cur| : (current = cur.next) {
                if (cur.data == value) {
                    // If the current node is the head, point head to the next node.
                    if (self.head.? == cur) {
                        self.head = cur.next;
                    }
                    // If the current node is the tail, point tail to its previous node.
                    if (self.tail.? == cur) {
                        self.tail = previous;
                    }
                    // Skip the current node and update the previous node to point to the next node.
                    if (previous) |*prev| {
                        prev.*.next = cur.next;
                    }
                    self.allocator.destroy(cur);
                    self.len -= 1;
                    return true;
                }

                previous = cur;
            }

            return false;
        }

        fn search(self: *Self, value: T) bool {
            var head: ?*Node = self.head;
            while (head) |h| : (head = h.next) {
                if (h.data == value) {
                    return true;
                }
            }
            return false;
        }

        fn visit(self: *Self, visitor: *const fn (i: usize, v: T) anyerror!void) !usize {
            var head = self.head;
            var i: usize = 0;
            while (head) |n| : (i += 1) {
                try visitor(i, n.data);
                head = n.next;
            }

            return i;
        }

        fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |n| {
                const next = n.next;
                self.allocator.destroy(n);
                current = next;
            }
            self.head = null;
            self.tail = null;
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lst = LinkedList(u32).init(allocator);
    defer lst.deinit();

    const values = [_]u32{ 32, 20, 21 };
    for (values) |v| {
        try lst.add(v);
    }

    try std.testing.expectEqual(lst.len, values.len);
    try std.testing.expectEqual(
        try lst.visit(struct {
            fn visitor(i: usize, v: u32) !void {
                try std.testing.expectEqual(values[i], v);
            }
        }.visitor),
        3,
    );

    try std.testing.expect(lst.search(20));

    // Test delete head
    try std.testing.expect(lst.remove(32));
    try std.testing.expectEqual(
        try lst.visit(struct {
            fn visitor(i: usize, v: u32) !void {
                try std.testing.expectEqual(([_]u32{ 20, 21 })[i], v);
            }
        }.visitor),
        2,
    );

    // Test delete tail
    try std.testing.expect(lst.remove(21));
    try std.testing.expectEqual(
        try lst.visit(struct {
            fn visitor(i: usize, v: u32) !void {
                try std.testing.expectEqual(([_]u32{20})[i], v);
            }
        }.visitor),
        1,
    );

    // Test delete head and tail at the same time
    try std.testing.expect(lst.remove(20));
    try std.testing.expectEqual(
        try lst.visit(struct {
            fn visitor(_: usize, _: u32) !void {
                unreachable;
            }
        }.visitor),
        0,
    );

    try std.testing.expectEqual(lst.len, 0);
}
```


[Singly linked list]: https://en.wikipedia.org/wiki/Linked_list

---

# Doubly Linked List

A [doubly linked list] contains nodes that are linked together in both directions, allowing for more efficient operations in some scenarios. Each node in a doubly linked list contains:
- `data`, the value stored in the node.
- `next`, a pointer to the next node in the list.
- `prev`, a pointer to the previous node in the list.

The list itself maintains:
- `head`, the head of the list, used for traversal from the start.
- `tail`, the tail of the list, used for traversal from the end and fast additions.
- `len`, the length of the list, tracking the number of nodes.

Operations that can be performed on doubly linked lists include:
- Insertion at the end O(1), based on the `tail` pointer.
- Insertion at arbitrary positions O(n), due to traversal requirements.
- Deletion O(n), with improved efficiency compared to singly linked lists it could easily find and remove nodes in this list without a full traversal.


```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

fn DoublyLinkedList(comptime T: type) type {
    return struct {
        const Node = struct {
            data: T,
            next: ?*Node = null,
            prev: ?*Node = null,
        };

        const Self = @This();

        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize = 0,
        allocator: Allocator,

        fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        // This function is equals to self.insertAt(self.len, value)
        // But this cost O(1), while insertAt cost O(n) .
        fn insertLast(self: *Self, value: T) !void {
            const node = try self.allocator.create(Node);
            node.* = Node{ .data = value, .prev = self.tail };
            if (self.tail) |tail| {
                tail.*.next = node;
            } else {
                self.head = node;
            }

            self.tail = node;
            self.len += 1;
        }

        fn insertAt(self: *Self, position: usize, value: T) !void {
            if (position > self.len) {
                return error.OutOfRange;
            }
            defer self.len += 1;

            const node = try self.allocator.create(Node);
            node.* = Node{ .data = value };

            var current = self.head;
            // Find the node which is specified by the position
            for (0..position) |_| {
                if (current) |cur| {
                    current = cur.next;
                }
            }

            // Put node in front of current
            node.next = current;
            if (current) |cur| {
                node.*.prev = cur.prev;

                if (cur.prev) |*prev| {
                    prev.*.next = node;
                } else {
                    // When current has no prev, we are insert at head.
                    self.head = node;
                }

                cur.*.prev = node;
            } else { // We are insert at tail, update node to new tail.
                if (self.tail) |tail| {
                    node.*.prev = tail;
                    tail.*.next = node;
                }
                self.tail = node;
                // Head may also be null for an empty list
                if (null == self.head) {
                    self.head = node;
                }
            }
        }

        fn remove(self: *Self, value: T) bool {
            var current = self.head;

            while (current) |cur| : (current = cur.next) {
                if (cur.data == value) {
                    // if the current node has a previous node
                    // then set the previous node's next to the current node's next
                    if (cur.prev) |prev| {
                        prev.next = cur.next;
                    } else {
                        // if the current node has no previous node
                        self.head = cur.next;
                    }

                    // if the current node has a next node
                    // then set the next node's previous to the current node's previous
                    if (cur.next) |next| {
                        next.prev = cur.prev;
                    } else {
                        //  if the current node has no next node
                        // then set the tail to the current node's previous
                        self.tail = cur.prev;
                    }

                    self.allocator.destroy(cur);
                    self.len -= 1;

                    return true;
                }
            }

            return false;
        }

        fn search(self: *Self, value: T) bool {
            var current: ?*Node = self.head;

            while (current) |cur| : (current = cur.next) {
                if (cur.data == value) {
                    return true;
                }
            }

            return false;
        }

        fn visit(self: Self, visitor: *const fn (i: usize, v: T) anyerror!void) !usize {
            var current: ?*Node = self.head;
            var i: usize = 0;

            while (current) |cur| : (i += 1) {
                try visitor(i, cur.data);
                current = cur.next;
            }

            return i;
        }

        fn visitBackwards(self: Self, visitor: *const fn (i: usize, v: T) anyerror!void) !usize {
            var current = self.tail;
            var i: usize = 0;

            while (current) |cur| : (i += 1) {
                try visitor(i, cur.data);
                current = cur.prev;
            }
            return i;
        }

        fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |cur| {
                const next = cur.next;
                self.allocator.destroy(cur);

                current = next;
            }

            self.head = null;
            self.tail = null;
            self.len = 0;
        }
    };
}

fn ensureList(lst: DoublyLinkedList(u32), comptime expected: []const u32) !void {
    const visited_times = try lst.visit(struct {
        fn visitor(i: usize, v: u32) !void {
            if (expected.len == 0) {
                unreachable;
            } else {
                try std.testing.expectEqual(v, expected[i]);
            }
        }
    }.visitor);
    try std.testing.expectEqual(visited_times, expected.len);

    const visited_times2 = try lst.visitBackwards(struct {
        fn visitor(i: usize, v: u32) !void {
            if (expected.len == 0) {
                unreachable;
            } else {
                try std.testing.expectEqual(v, expected[expected.len - i - 1]);
            }
        }
    }.visitor);
    try std.testing.expectEqual(visited_times2, expected.len);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var list = DoublyLinkedList(u32).init(allocator);
    defer list.deinit();

    const values = [_]u32{ 1, 2, 3, 4, 5 };

    for (values) |value| {
        try list.insertLast(value);
    }
    try ensureList(list, &values);

    try list.insertAt(1, 100);
    try ensureList(list, &[_]u32{ 1, 100, 2, 3, 4, 5 });

    try list.insertAt(0, 200);
    try ensureList(list, &[_]u32{ 200, 1, 100, 2, 3, 4, 5 });

    try std.testing.expect(list.remove(100));
    try ensureList(list, &[_]u32{ 200, 1, 2, 3, 4, 5 });

    // delete all
    for (values) |value| {
        try std.testing.expect(list.remove(value));
    }
    try std.testing.expect(list.remove(200));
    try ensureList(list, &[_]u32{});
}
```


[doubly linked list]: https://en.wikipedia.org/wiki/Doubly_linked_list

---

# Argument Parsing

Parsing arguments is common in command line programs and there are some packages in Zig to make this task easier. To name a few:

- [Hejsil/zig-clap](https://github.com/Hejsil/zig-clap)
- [MasterQ32/zig-args](https://github.com/MasterQ32/zig-args/)
- [simargs](https://zigcli.liujiacai.net/modules/simargs/)

Here we will give an example using `simargs`.

```zig
const std = @import("std");
const print = std.debug.print;
const simargs = @import("simargs");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var opt = try simargs.parse(allocator, struct {
        // Those fields declare arguments options
        // only `output` is required, others are all optional
        verbose: ?bool,
        @"user-agent": enum { Chrome, Firefox, Safari } = .Firefox,
        timeout: ?u16 = 30, // default value
        output: []const u8 = "/tmp",
        help: bool = false,

        // This declares option's short name
        pub const __shorts__ = .{
            .verbose = .v,
            .output = .o,
            .@"user-agent" = .A,
            .help = .h,
        };

        // This declares option's help message
        pub const __messages__ = .{
            .verbose = "Make the operation more talkative",
            .output = "Write to file instead of stdout",
            .timeout = "Max time this request can cost",
        };
    }, "[file]", null);
    defer opt.deinit();

    const sep = "-" ** 30;
    print("{s}Program{s}\n{s}\n\n", .{ sep, sep, opt.program });
    print("{s}Arguments{s}\n", .{ sep, sep });
    inline for (std.meta.fields(@TypeOf(opt.args))) |fld| {
        const format = "{s:>10}: " ++ switch (fld.type) {
            []const u8 => "{s}",
            ?[]const u8 => "{?s}",
            else => "{any}",
        } ++ "\n";
        print(format, .{ fld.name, @field(opt.args, fld.name) });
    }

    print("\n{s}Positionals{s}\n", .{ sep, sep });
    for (opt.positional_args, 0..) |arg, idx| {
        print("{d}: {s}\n", .{ idx + 1, arg });
    }

    // Provide a print_help util method
    print("\n{s}print_help{s}\n", .{ sep, sep });
    const stdout = std.fs.File.stdout();
    var buf: [1024]u8 = undefined;
    var writer = stdout.writer(&buf);
    try opt.printHelp(&writer.interface);
}
```

---

# Database

This section will demonstrate how to connect to popular databases from Zig.

Data model used is as follows:

1. Create two tables: `cat_colors`, `cats`, `cats` has a reference in `cat_colors`.
2. Create a prepare statement for each table, and insert data.
3. Execute a join query to get `cat_name` and `color_name` at the same time.

## cat_colors

| id  | name  |
| --- | ----- |
| 1   | Blue  |
| 2   | Black |

## cats

| id  | name    | color_id |
| --- | ------- | -------- |
| 1   | Tigger  | 1        |
| 2   | Sammy   | 1        |
| 3   | Oreo    | 2        |
| 4   | Biscuit | 2        |

---

# SQLite

Although there are some [wrapper package](https://github.com/vrischmann/zig-sqlite) options for SQLite in Zig, they are unstable. So here we will introduce the [C API interface](https://www.sqlite.org/cintro.html).

Data models are introduced [here](https://cookbook.ziglang.cc/database/).

```zig
/// SQLite API demo
/// https://www.sqlite.org/cintro.html
///
const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const print = std.debug.print;

const DB = struct {
    db: *c.sqlite3,

    fn init(db: *c.sqlite3) DB {
        return .{ .db = db };
    }

    fn deinit(self: DB) void {
        _ = c.sqlite3_close(self.db);
    }

    fn execute(self: DB, query: [:0]const u8) !void {
        var errmsg: [*c]u8 = undefined;
        if (c.SQLITE_OK != c.sqlite3_exec(self.db, query, null, null, &errmsg)) {
            defer c.sqlite3_free(errmsg);
            print("Exec query failed: {s}\n", .{errmsg});
            return error.execError;
        }
        return;
    }

    fn queryTable(self: DB) !void {
        const stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const query =
                \\ SELECT
                \\     c.name,
                \\     cc.name
                \\ FROM
                \\     cats c
                \\     INNER JOIN cat_colors cc ON cc.id = c.color_id;
                \\
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(self.db, query, query.len + 1, &stmt, null)) {
                print("Can't create prepare statement: {s}\n", .{c.sqlite3_errmsg(self.db)});
                return error.prepareStmt;
            }
            break :blk stmt.?;
        };
        defer _ = c.sqlite3_finalize(stmt);

        var rc = c.sqlite3_step(stmt);
        while (rc == c.SQLITE_ROW) {
            // iCol is 0-based.
            // Those return text are invalidated when call step, reset, finalize are called
            // https://www.sqlite.org/c3ref/column_blob.html
            const cat_name = c.sqlite3_column_text(stmt, 0);
            const color_name = c.sqlite3_column_text(stmt, 1);

            print("Cat {s} is in {s} color\n", .{ cat_name, color_name });
            rc = c.sqlite3_step(stmt);
        }

        if (rc != c.SQLITE_DONE) {
            print("Step query failed: {s}\n", .{c.sqlite3_errmsg(self.db)});
            return error.stepQuery;
        }
    }

    fn insertTable(self: DB) !void {
        const insert_color_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const query = "INSERT INTO cat_colors (name) values (?1)";
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(self.db, query, query.len + 1, &stmt, null)) {
                print("Can't create prepare statement: {s}\n", .{c.sqlite3_errmsg(self.db)});
                return error.prepareStmt;
            }
            break :blk stmt.?;
        };
        defer _ = c.sqlite3_finalize(insert_color_stmt);

        const insert_cat_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const query = "INSERT INTO cats (name, color_id) values (?1, ?2)";
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(self.db, query, query.len + 1, &stmt, null)) {
                print("Can't create prepare statement: {s}\n", .{c.sqlite3_errmsg(self.db)});
                return error.prepareStmt;
            }
            break :blk stmt.?;
        };
        defer _ = c.sqlite3_finalize(insert_cat_stmt);

        const cat_colors = .{
            .{
                "Blue", .{
                    "Tigger",
                    "Sammy",
                },
            },
            .{
                "Black", .{
                    "Oreo",
                    "Biscuit",
                },
            },
        };

        inline for (cat_colors) |row| {
            const color = row.@"0";
            const cat_names = row.@"1";

            // bind index is 1-based.
            if (c.SQLITE_OK != c.sqlite3_bind_text(insert_color_stmt, 1, color, color.len, c.SQLITE_STATIC)) {
                print("Can't bind text: {s}\n", .{c.sqlite3_errmsg(self.db)});
                return error.bindText;
            }
            if (c.SQLITE_DONE != c.sqlite3_step(insert_color_stmt)) {
                print("Can't step color stmt: {s}\n", .{c.sqlite3_errmsg(self.db)});
                return error.step;
            }

            _ = c.sqlite3_reset(insert_color_stmt);

            const last_id = c.sqlite3_last_insert_rowid(self.db);
            inline for (cat_names) |cat_name| {
                if (c.SQLITE_OK != c.sqlite3_bind_text(insert_cat_stmt, 1, cat_name, cat_name.len, c.SQLITE_STATIC)) {
                    print("Can't bind cat name: {s}\n", .{c.sqlite3_errmsg(self.db)});
                    return error.bindText;
                }
                if (c.SQLITE_OK != c.sqlite3_bind_int64(insert_cat_stmt, 2, last_id)) {
                    print("Can't bind cat color_id: {s}\n", .{c.sqlite3_errmsg(self.db)});
                    return error.bindText;
                }
                if (c.SQLITE_DONE != c.sqlite3_step(insert_cat_stmt)) {
                    print("Can't step cat stmt: {s}\n", .{c.sqlite3_errmsg(self.db)});
                    return error.step;
                }

                _ = c.sqlite3_reset(insert_cat_stmt);
            }
        }

        return;
    }
};

pub fn main() !void {
    const version = c.sqlite3_libversion();
    print("libsqlite3 version is {s}\n", .{version});

    var c_db: ?*c.sqlite3 = undefined;
    if (c.SQLITE_OK != c.sqlite3_open(":memory:", &c_db)) {
        print("Can't open database: {s}\n", .{c.sqlite3_errmsg(c_db)});
        return;
    }
    const db = DB.init(c_db.?);
    defer db.deinit();

    try db.execute(
        \\ create table if not exists cat_colors (
        \\   id integer primary key,
        \\   name text not null unique
        \\ );
        \\ create table if not exists cats (
        \\   id integer primary key,
        \\   name text not null,
        \\   color_id integer not null references cat_colors(id)
        \\ );
    );

    try db.insertTable();
    try db.queryTable();
}
```

---

# Postgres

As with [previous section](https://cookbook.ziglang.cc/14-01-sqlite/), here we introduce [libpq](https://www.postgresql.org/docs/16/libpq-example.html) interface directly, other than [wrapper package](https://github.com/tonis2/zig-postgres).

Data models used in this demo are the same with the one used in [SQLite section](https://cookbook.ziglang.cc/14-01-sqlite/).

> Note: After executing a query with `PQexec` like functions, if there are returning results, check the result with `PGRES_TUPLES_OK`, otherwise `PGRES_COMMAND_OK` should be used.

- <https://www.postgresql.org/docs/current/libpq-exec.html#LIBPQ-PQRESULTSTATUS>

```zig
//! Libpq API example
//! https://gist.github.com/jiacai2050/00709b98ee69d73d022d2f293555f08f
//! https://www.postgresql.org/docs/16/libpq-example.html
//!
const std = @import("std");
const print = std.debug.print;
const c = @cImport({
    @cInclude("libpq-fe.h");
});

const DB = struct {
    conn: *c.PGconn,

    fn init(conn_info: [:0]const u8) !DB {
        const conn = c.PQconnectdb(conn_info);
        if (c.PQstatus(conn) != c.CONNECTION_OK) {
            print("Connect failed, err: {s}\n", .{c.PQerrorMessage(conn)});
            return error.connect;
        }
        return DB{ .conn = conn.? };
    }

    fn deinit(self: DB) void {
        c.PQfinish(self.conn);
    }

    // Execute a query without returning any data.
    fn exec(self: DB, query: [:0]const u8) !void {
        const result = c.PQexec(self.conn, query);
        defer c.PQclear(result);

        if (c.PQresultStatus(result) != c.PGRES_COMMAND_OK) {
            print("exec query failed, query:{s}, err: {s}\n", .{ query, c.PQerrorMessage(self.conn) });
            return error.Exec;
        }
    }

    fn insertTable(self: DB) !void {
        // 1. create two prepared statements.
        {
            // There is no `get_last_insert_rowid` in libpq, so we use RETURNING id to get the last insert id.
            const res = c.PQprepare(
                self.conn,
                "insert_cat_colors",
                "INSERT INTO cat_colors (name) VALUES ($1) returning id",
                1, // nParams, number of parameters supplied
                // Specifies, by OID, the data types to be assigned to the parameter symbols.
                // When null, the server infers a data type for the parameter symbol in the same way it would do for an untyped literal string.
                null, // paramTypes.
            );
            defer c.PQclear(res);
            if (c.PQresultStatus(res) != c.PGRES_COMMAND_OK) {
                print("prepare insert cat_colors failed, err: {s}\n", .{c.PQerrorMessage(self.conn)});
                return error.prepare;
            }
        }
        {
            const res = c.PQprepare(self.conn, "insert_cats", "INSERT INTO cats (name, color_id) VALUES ($1, $2)", 2, null);
            defer c.PQclear(res);
            if (c.PQresultStatus(res) != c.PGRES_COMMAND_OK) {
                print("prepare insert cats failed, err: {s}\n", .{c.PQerrorMessage(self.conn)});
                return error.prepare;
            }
        }
        const cat_colors = .{
            .{
                "Blue", .{
                    "Tigger",
                    "Sammy",
                },
            },
            .{
                "Black", .{
                    "Oreo",
                    "Biscuit",
                },
            },
        };

        // 2. Use prepared statements to insert data.
        inline for (cat_colors) |row| {
            const color = row.@"0";
            const cat_names = row.@"1";
            const color_id = blk: {
                const res = c.PQexecPrepared(
                    self.conn,
                    "insert_cat_colors",
                    1, // nParams
                    &[_][*c]const u8{color}, // paramValues
                    &[_]c_int{color.len}, // paramLengths
                    &[_]c_int{0}, // paramFormats
                    0, // resultFormat
                );
                defer c.PQclear(res);

                // Since this insert has returns, so we check res with PGRES_TUPLES_OK
                if (c.PQresultStatus(res) != c.PGRES_TUPLES_OK) {
                    print("exec insert cat_colors failed, err: {s}\n", .{c.PQresultErrorMessage(res)});
                    return error.InsertCatColors;
                }
                break :blk std.mem.span(c.PQgetvalue(res, 0, 0));
            };
            inline for (cat_names) |name| {
                const res = c.PQexecPrepared(
                    self.conn,
                    "insert_cats",
                    2, // nParams
                    &[_][*c]const u8{ name, color_id }, // paramValues
                    &[_]c_int{ name.len, @intCast(color_id.len) }, // paramLengths
                    &[_]c_int{ 0, 0 }, // paramFormats
                    0, // resultFormat, 0 means text, 1 means binary.
                );
                defer c.PQclear(res);

                // This insert has no returns, so we check res with PGRES_COMMAND_OK
                if (c.PQresultStatus(res) != c.PGRES_COMMAND_OK) {
                    print("exec insert cats failed, err: {s}\n", .{c.PQresultErrorMessage(res)});
                    return error.InsertCats;
                }
            }
        }
    }

    fn queryTable(self: DB) !void {
        const query =
            \\ SELECT
            \\     c.name,
            \\     cc.name
            \\ FROM
            \\     cats c
            \\     INNER JOIN cat_colors cc ON cc.id = c.color_id;
            \\
        ;

        const result = c.PQexec(self.conn, query);
        defer c.PQclear(result);

        if (c.PQresultStatus(result) != c.PGRES_TUPLES_OK) {
            print("exec query failed, query:{s}, err: {s}\n", .{ query, c.PQerrorMessage(self.conn) });
            return error.queryTable;
        }

        const num_rows = c.PQntuples(result);
        for (0..@intCast(num_rows)) |row| {
            const cat_name = std.mem.span(c.PQgetvalue(result, @intCast(row), 0));
            const color_name = std.mem.span(c.PQgetvalue(result, @intCast(row), 1));
            print("Cat {s} is in {s} color\n", .{ cat_name, color_name });
        }
    }
};

pub fn main() !void {
    const conn_info = "host=127.0.0.1 user=postgres password=postgres dbname=postgres";

    const db = try DB.init(conn_info);
    defer db.deinit();

    try db.exec(
        \\ create table if not exists cat_colors (
        \\   id integer primary key generated always as identity,
        \\   name text not null unique
        \\ );
        \\ create table if not exists cats (
        \\   id integer primary key generated always as identity,
        \\   name text not null,
        \\   color_id integer not null references cat_colors(id)
        \\ );
    );

    try db.insertTable();
    try db.queryTable();
}
```

---

# MySQL

As with [sqlite section](https://cookbook.ziglang.cc/14-01-sqlite/), here we introduce [libmysqlclient](https://dev.mysql.com/doc/c-api/8.0/en/c-api-basic-interface-usage.html) interface directly.

Data models are introduced [here](https://cookbook.ziglang.cc/database/).

> Note: After executing a query with `mysql_real_query` like functions, if there are returning results, we must consume the result, otherwise we will get following error when we execute next query.

```
Commands out of sync; you can't run this command now
```

- <https://dev.mysql.com/doc/c-api/8.0/en/mysql-next-result.html>

```zig
//! MySQL 8.0 API demo
//! https://dev.mysql.com/doc/c-api/8.0/en/c-api-basic-interface-usage.html
//!
const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("mysql.h");
});
const print = std.debug.print;

pub const DBInfo = struct {
    host: [:0]const u8,
    user: [:0]const u8,
    password: [:0]const u8,
    database: [:0]const u8,
    port: u32 = 3306,
};

pub const DB = struct {
    conn: *c.MYSQL,
    allocator: Allocator,

    fn init(allocator: Allocator, db_info: DBInfo) !DB {
        const db = c.mysql_init(null);

        if (db == null) {
            return error.initError;
        }

        if (c.mysql_real_connect(
            db,
            db_info.host,
            db_info.user,
            db_info.password,
            db_info.database,
            db_info.port,
            null,
            c.CLIENT_MULTI_STATEMENTS,
        ) == null) {
            print("Connect to database failed: {s}\n", .{c.mysql_error(db)});
            return error.connectError;
        }

        return .{
            .conn = db,
            .allocator = allocator,
        };
    }

    fn deinit(self: DB) void {
        c.mysql_close(self.conn);
    }

    fn execute(self: DB, query: []const u8) !void {
        if (c.mysql_real_query(self.conn, query.ptr, query.len) != 0) {
            print("Exec query failed: {s}\n", .{c.mysql_error(self.conn)});
            return error.execError;
        }
    }

    fn queryTable(self: DB) !void {
        const query =
            \\ SELECT
            \\     c.name,
            \\     cc.name
            \\ FROM
            \\     cats c
            \\     INNER JOIN cat_colors cc ON cc.id = c.color_id;
            \\
        ;

        try self.execute(query);
        const result = c.mysql_store_result(self.conn);
        if (result == null) {
            print("Store result failed: {s}\n", .{c.mysql_error(self.conn)});
            return error.storeResultError;
        }
        defer c.mysql_free_result(result);

        while (c.mysql_fetch_row(result)) |row| {
            const cat_name = row[0];
            const color_name = row[1];
            print("Cat: {s}, Color: {s}\n", .{ cat_name, color_name });
        }
    }

    fn insertTable(self: DB) !void {
        const cat_colors = .{
            .{
                "Blue",
                .{ "Tigger", "Sammy" },
            },
            .{
                "Black",
                .{ "Oreo", "Biscuit" },
            },
        };

        const insert_color_stmt: *c.MYSQL_STMT = blk: {
            const stmt = c.mysql_stmt_init(self.conn);
            if (stmt == null) {
                return error.initStmt;
            }
            errdefer _ = c.mysql_stmt_close(stmt);

            const insert_color_query = "INSERT INTO cat_colors (name) values (?)";
            if (c.mysql_stmt_prepare(stmt, insert_color_query, insert_color_query.len) != 0) {
                print("Prepare color stmt failed, msg:{s}\n", .{c.mysql_error(self.conn)});
                return error.prepareStmt;
            }

            break :blk stmt.?;
        };
        defer _ = c.mysql_stmt_close(insert_color_stmt);

        const insert_cat_stmt = blk: {
            const stmt = c.mysql_stmt_init(self.conn);
            if (stmt == null) {
                return error.initStmt;
            }
            errdefer _ = c.mysql_stmt_close(stmt);

            const insert_cat_query = "INSERT INTO cats (name, color_id) values (?, ?)";
            if (c.mysql_stmt_prepare(stmt, insert_cat_query, insert_cat_query.len) != 0) {
                print("Prepare cat stmt failed: {s}\n", .{c.mysql_error(self.conn)});
                return error.prepareStmt;
            }

            break :blk stmt.?;
        };
        defer _ = c.mysql_stmt_close(insert_cat_stmt);

        inline for (cat_colors) |row| {
            const color = row.@"0";
            const cat_names = row.@"1";

            var color_binds = [_]c.MYSQL_BIND{std.mem.zeroes(c.MYSQL_BIND)};
            color_binds[0].buffer_type = c.MYSQL_TYPE_STRING;
            color_binds[0].buffer_length = color.len;
            color_binds[0].is_null = 0;
            color_binds[0].buffer = @constCast(@ptrCast(color.ptr));

            if (c.mysql_stmt_bind_param(insert_color_stmt, &color_binds)) {
                print("Bind color param failed: {s}\n", .{c.mysql_error(self.conn)});
                return error.bindParamError;
            }
            if (c.mysql_stmt_execute(insert_color_stmt) != 0) {
                print("Exec color stmt failed: {s}\n", .{c.mysql_error(self.conn)});
                return error.execStmtError;
            }
            const last_id = c.mysql_stmt_insert_id(insert_color_stmt);
            _ = c.mysql_stmt_reset(insert_color_stmt);

            inline for (cat_names) |cat_name| {
                var cat_binds = [_]c.MYSQL_BIND{ std.mem.zeroes(c.MYSQL_BIND), std.mem.zeroes(c.MYSQL_BIND) };
                cat_binds[0].buffer_type = c.MYSQL_TYPE_STRING;
                cat_binds[0].buffer_length = cat_name.len;
                cat_binds[0].buffer = @constCast(@ptrCast(cat_name.ptr));

                cat_binds[1].buffer_type = c.MYSQL_TYPE_LONG;
                cat_binds[1].length = (@as(c_ulong, 1));
                cat_binds[1].buffer = @constCast(@ptrCast(&last_id));

                if (c.mysql_stmt_bind_param(insert_cat_stmt, &cat_binds)) {
                    print("Bind cat param failed: {s}\n", .{c.mysql_error(self.conn)});
                    return error.bindParamError;
                }
                if (c.mysql_stmt_execute(insert_cat_stmt) != 0) {
                    print("Exec cat stmt failed: {s}\n", .{c.mysql_error(self.conn)});
                    return error.execStmtError;
                }

                _ = c.mysql_stmt_reset(insert_cat_stmt);
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const version = c.mysql_get_client_version();
    print("MySQL client version is {}\n", .{version});

    const db = try DB.init(allocator, .{
        .database = "public",
        .host = "127.0.0.1",
        .user = "root",
        .password = "root",
    });
    defer db.deinit();

    try db.execute(
        \\ CREATE TABLE IF NOT EXISTS cat_colors (
        \\  id INT AUTO_INCREMENT PRIMARY KEY,
        \\  name VARCHAR(255) NOT NULL
        \\);
        \\
        \\CREATE TABLE IF NOT EXISTS cats (
        \\  id INT AUTO_INCREMENT PRIMARY KEY,
        \\  name VARCHAR(255) NOT NULL,
        \\  color_id INT NOT NULL
        \\)
    );
    // Since we use multi-statement, we need to consume all results.
    // Otherwise we will get following error when we execute next query.
    // Commands out of sync; you can't run this command now
    //
    // https://dev.mysql.com/doc/c-api/8.0/en/mysql-next-result.html
    while (c.mysql_next_result(db.conn) == 0) {
        const res = c.mysql_store_result(db.conn);
        c.mysql_free_result(res);
    }

    try db.insertTable();
    try db.queryTable();
}
```

---

# Regular Expressions

Currently there is no regex support in Zig, so the best way to go is binding with Posix's [regex.h](https://pubs.opengroup.org/onlinepubs/7908799/xsh/regex.h.html).

Interop with C is easy in Zig, but since translate-c doesn't support bitfields, we can't use `regex_t` directly. So here we create a [static C library](https://github.com/zigcc/zig-cookbook/blob/460dea1f2f9937ab512a70683aacab79e34c723a/build.zig#L50) first, providing two functions:

```c
regex_t* alloc_regex_t(void);
void free_regex_t(regex_t* ptr);
```

`regex_t*` is a pointer, it has fixed size, so we can use it directly in Zig.

```zig
const std = @import("std");
const print = std.debug.print;
const c = @cImport({
    @cInclude("regex.h");
    // This is our static library.
    @cInclude("regex_slim.h");
});

const Regex = struct {
    inner: *c.regex_t,

    fn init(pattern: [:0]const u8) !Regex {
        const inner = c.alloc_regex_t().?;
        if (0 != c.regcomp(inner, pattern, c.REG_NEWLINE | c.REG_EXTENDED)) {
            return error.compile;
        }

        return .{
            .inner = inner,
        };
    }

    fn deinit(self: Regex) void {
        c.free_regex_t(self.inner);
    }

    fn matches(self: Regex, input: [:0]const u8) bool {
        const match_size = 1;
        var pmatch: [match_size]c.regmatch_t = undefined;
        return 0 == c.regexec(self.inner, input, match_size, &pmatch, 0);
    }

    fn exec(self: Regex, input: [:0]const u8) !void {
        const match_size = 1;
        var pmatch: [match_size]c.regmatch_t = undefined;

        var i: usize = 0;
        var string = input;
        const expected = [_][]const u8{ "John Do", "John Foo" };
        while (true) {
            if (0 != c.regexec(self.inner, string, match_size, &pmatch, 0)) {
                break;
            }

            const slice = string[@as(usize, @intCast(pmatch[0].rm_so))..@as(usize, @intCast(pmatch[0].rm_eo))];

            try std.testing.expectEqualStrings(expected[i], slice);

            string = string[@intCast(pmatch[0].rm_eo)..];
            i += 1;
        }

        try std.testing.expectEqual(i, 2);
    }
};

pub fn main() !void {
    {
        const regex = try Regex.init("[ab]c");
        defer regex.deinit();

        try std.testing.expect(regex.matches("bc"));
        try std.testing.expect(!regex.matches("cc"));
    }

    {
        const regex = try Regex.init("John.*o");
        defer regex.deinit();

        try regex.exec(
            \\ 1) John Driverhacker;
            \\ 2) John Doe;
            \\ 3) John Foo;
            \\
        );
    }
}
```


## References

- [regex(3) — Linux manual page](https://man7.org/linux/man-pages/man3/regex.3.html)
- [How to allocate a struct of incomplete type in Zig?](https://stackoverflow.com/a/73095054)
- [Regular Expressions in Zig](https://www.openmymind.net/Regular-Expressions-in-Zig/)

---

# String Parsing

## String to number/enum

```zig
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const parseInt = std.fmt.parseInt;
const parseFloat = std.fmt.parseFloat;
const stringToEnum = std.meta.stringToEnum;

pub fn main() !void {
    try expectEqual(parseInt(i32, "123", 10), 123);
    try expectEqual(parseInt(i32, "-123", 10), -123);
    try expectError(error.Overflow, parseInt(u4, "123", 10));

    // 0 means auto detect the base.
    // base = 16
    try expectEqual(parseInt(i32, "0xF", 0), 15);
    // base = 2
    try expectEqual(parseInt(i32, "0b1111", 0), 15);
    // base = 8
    try expectEqual(parseInt(i32, "0o17", 0), 15);

    try expectEqual(parseFloat(f32, "1.23"), 1.23);
    try expectEqual(parseFloat(f32, "-1.23"), -1.23);

    const Color = enum {
        Red,
        Blue,
        Green,
    };
    try expectEqual(stringToEnum(Color, "Red").?, Color.Red);
    try expectEqual(stringToEnum(Color, "Yello"), null);
}
```
