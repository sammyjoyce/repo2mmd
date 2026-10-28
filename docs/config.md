# repo2mmd Configuration Guide

_Last updated: 2025-10-06_

repo2mmd reads configuration from three sources, in descending order of priority:

1. **CLI flags** (`repo2mmd graph --type call`).
2. **Environment variables** (`REPO2MMD_*`).
3. **Configuration file** (`repo2mmd.toml` located in the repository root).

Values set via higher-priority layers override lower ones. unset keys fall back to safe defaults baked into the binary.

## 1. CLI Flags

All subcommands share the `--config` flag to override the default config path. The `graph` command exposes the primary knobs:

```
repo2mmd graph [PATH] \
  --type deps|call|class|include \
  --lang auto|zig|c|ts|<plugin-id>[,...] \
  --scope repo|dir:<glob>|module:<name> \
  --entry <fqname[,..]> \
  --group-by package|dir|module|type \
  --prune "degree>200 OR depth>5" \
  --layout LR|TB \
  --format mmd|json|dot \
  --out <path> \
  --link-src "https://host/rev/{path}#L{line}" \
  --threads <n> \
  --max-bytes <bytes> \
  --no-cache \
  --ci \
  --max-unresolved <n>
```

## 2. Environment Variables

| Variable | Description | Example |
| --- | --- | --- |
| `REPO2MMD_CONFIG` | Override config file path. | `/tmp/custom.toml` |
| `REPO2MMD_LANGS` | Comma-separated language allowlist. | `zig,c,ts` |
| `REPO2MMD_CACHE_DIR` | Custom cache directory. | `/tmp/.r2m-cache` |
| `REPO2MMD_THREADS` | Default worker count. | `4` |
| `REPO2MMD_LOG_LEVEL` | `info`, `debug`, or `trace`. | `debug` |
| `REPO2MMD_IGNORE` | Extra ignore globs (comma-separated). | `**/vendor/**,**/*.gen.ts` |

Environment variables are parsed before the config file and can be used in CI to switch modes without editing repository files.

## 3. Configuration File (`repo2mmd.toml`)

repo2mmd looks for `repo2mmd.toml` in the working tree root. Use `repo2mmd init` to scaffold a starter file.

### 3.1 Example

```toml
[general]
languages = ["zig", "c", "ts"]
default_graph = "deps"
threads = 0                # 0 = auto (min(cores, 8))
max_bytes = "2g"
ignore = ["**/build/**", "**/.cache/**"]

[output]
format = "mmd"
layout = "LR"
group_by = "module"
link_src = "https://host/rev/{path}#L{line}"
chunk_threshold = 250

[cache]
dir = ".repo2mmd/cache"
enabled = true

[ci]
max_unresolved = 10
fail_on_warn = false

[plugins]
trusted_dirs = ["./plugins"]

[trace]
enabled = false
```

### 3.2 Schema Summary

| Section | Keys | Notes |
| --- | --- | --- |
| `[general]` | `languages`, `default_graph`, `threads`, `max_bytes`, `ignore` | `max_bytes` accepts human-readable units (`512m`, `2g`). |
| `[output]` | `format`, `layout`, `group_by`, `link_src`, `chunk_threshold` | `format` may be `mmd`, `json`, or `dot`. |
| `[cache]` | `dir`, `enabled` | Disabled cache forces cold parses. |
| `[ci]` | `max_unresolved`, `fail_on_warn` | When `fail_on_warn` is true, `warn` diagnostics trigger exit code 1. |
| `[plugins]` | `trusted_dirs`, `allow_unversioned` | `allow_unversioned` defaults to false to protect production runs. |
| `[trace]` | `enabled`, `output` | Trace mode is experimental and disabled by default. |

## 4. Configuration Resolution

The runtime merges configuration using this algorithm:

1. Parse CLI flags into a high-priority map.
2. Populate defaults based on build options and operating system.
3. Load environment variables and override defaults.
4. Parse `repo2mmd.toml` (if present) and merge any keys not already set by CLI/env.
5. Finalise derived values (e.g., compute cache directory, expand user paths, normalise globs).

Conflicting settings (e.g., `--no-cache` with `cache.enabled = true`) resolve in favour of the highest-priority source; the final manifest records the resolved values.

## 5. Validation & Diagnostics

- Invalid keys produce a warning and are ignored to maintain forward compatibility.
- Mis-typed enums (e.g., `format = "jsonl"`) are rejected with an error pointing to the offending line.
- Globs leverage the same matcher as discovery; invalid patterns are reported during initialisation.
- Resolved values can be inspected via `repo2mmd init --print-config` which emits the effective configuration as JSON.

## 6. Tips

- Use environment variables in CI for secrets or ephemeral overrides, keeping `repo2mmd.toml` focused on repository defaults.
- When scripting, rely on `--format json` plus `--ci` to get deterministic output and failure semantics.
- Keep `ignore` lists targeted; discovery costs grow with redundant globs.
- To debug config resolution, run with `REPO2MMD_LOG_LEVEL=debug` and inspect the startup log block.

