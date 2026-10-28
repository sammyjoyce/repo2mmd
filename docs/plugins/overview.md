# repo2mmd Plugin Authoring Guide

_Last updated: 2025-10-06_

Language support in repo2mmd is implemented through dynamically-loaded plugins that conform to a stable C ABI. This guide describes how to build, test, and ship a plugin that integrates cleanly with the core runtime.

## 1. Quick Start

1. Include the exported headers from the release bundle (`include/ir.h`, `include/frontend.h`).
2. Implement the `repo2mmd_frontend_v1` vtable and export `repo2mmd_lang_frontend_v1()`.
3. Build a shared library (`.so` or `.dylib`) using the same C ABI calling conventions.
4. Place the compiled library in a directory passed via `--plugin-dir` or the default `plugins/` search path.
5. Run `repo2mmd cache prune && repo2mmd graph --lang your_lang` against sample fixtures to validate output.

## 2. ABI Reference

```c
typedef struct {
  const char *id;            // e.g. "rust"
  uint32_t api_version;      // set to R2M_FRONTEND_API_VERSION (currently 1)
  uint32_t schema_min;       // minimum supported IR schema
  uint32_t schema_max;       // maximum supported IR schema
  bool (*wants_file)(const r2m_path_view *path);
  bool (*parse_file)(const r2m_parse_request *req,
                     r2m_parse_response *res);
  bool (*post_resolve)(r2m_graph_t *graph); // optional
  void (*shutdown)(void);                   // optional
} repo2mmd_frontend_v1;
```

- `wants_file` receives a normalised POSIX path and returns whether the plugin should handle the file.
- `parse_file` is invoked with a per-file arena allocated by the core; the plugin must allocate all strings and structs using `res->arena_alloc` helpers.
- `post_resolve` allows final adjustments (e.g., language-specific alias flattening) after the core links references.
- `shutdown` is called once before the plugin is unloaded.

## 3. Memory & Ownership Rules

- The arena provided through `r2m_parse_request` is monotonic; plugins should not free allocations explicitly.
- No static/global mutable state should outlive `parse_file`. Cache per-worker data via thread-local storage if necessary.
- Strings must be UTF-8 and relative paths must use forward slashes.

## 4. Error Handling

- Return `false` from `parse_file` to signal a fatal error; include diagnostic entries via `r2m_diag_emit_error()` helpers so end users see actionable messages.
- Recoverable issues (missing includes, heuristic fallbacks) should produce `warn` diagnostics and continue.
- Avoid printing to stdout/stderr; use provided logging hooks when running in debug mode.

## 5. Testing Plugins

- **Unit tests.** Exercise syntax edge cases by constructing synthetic source strings and verifying emitted nodes/edges.
- **Golden tests.** Use the plugin harness (`zig build plugin-test -- your_lang`) to run fixtures and compare JSON IR snapshots against expected outputs.
- **Fuzzing.** Integrate with `zig build fuzz` by registering mutation handlers if the language grammar supports it.

## 6. Version Compatibility

- Bump the plugin’s internal version string whenever schema interactions change.
- Update `schema_min`/`schema_max` ranges when repo2mmd introduces new IR schema versions.
- The core loader will refuse to load plugins whose API or schema ranges do not overlap with the current runtime.

## 7. Distribution Checklist

- [ ] Build shared library for Linux (`.so`) and macOS (`.dylib`) if you plan to publish binaries.
- [ ] Include license and README describing supported language features and limitations.
- [ ] Provide fixtures under `test/plugins/<id>/` to keep regression coverage tight.
- [ ] Document any external dependencies (compilers, SDKs) required for advanced analysis.
- [ ] Submit a compatibility matrix (repo2mmd version vs. plugin version) if hosting publicly.

## 8. Sample Minimal Plugin (Pseudo-Code)

```c
static bool wants_file(const r2m_path_view *path) {
  return r2m_path_has_suffix(path, ".toy");
}

static bool parse_file(const r2m_parse_request *req,
                       r2m_parse_response *res) {
  r2m_node_t *node = r2m_arena_alloc_node(res->arena);
  *node = (r2m_node_t){
    .id = r2m_hash_symbol("toy::main"),
    .lang = R2M_LANG_CUSTOM,
    .kind = R2M_NK_FUNC,
    .name = r2m_arena_strdup(res->arena, "main"),
    .fqname = r2m_arena_strdup(res->arena, "toy::main"),
    .file = req->path->data,
    .range = req->range
  };
  r2m_push_node(res, node);
  return true;
}

static const repo2mmd_frontend_v1 PLUGIN = {
  .id = "toy",
  .api_version = R2M_FRONTEND_API_VERSION,
  .schema_min = 1,
  .schema_max = 1,
  .wants_file = wants_file,
  .parse_file = parse_file,
  .post_resolve = NULL,
  .shutdown = NULL,
};

const repo2mmd_frontend_v1 *repo2mmd_lang_frontend_v1(void) {
  return &PLUGIN;
}
```

## 9. Further Reading

- [docs/ARCHITECTURE.md](../ARCHITECTURE.md) — Overview of the runtime and pipeline.
- [docs/ir-schema.md](../ir-schema.md) — Full schema for nodes, edges, and manifests.
- [docs/config.md](../config.md) — Configuration file format and CLI precedence.
- [PLAN.md](../../PLAN.md) — Roadmap and acceptance criteria for upcoming releases.

