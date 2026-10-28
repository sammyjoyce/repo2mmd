# repo2mmd IR Schema Reference

_Last updated: 2025-10-07_

The repo2mmd intermediate representation (IR) is a language-neutral graph exchanged between the core runtime, emitters, and language plugins. This document defines the schema exposed via the `--format json` output and referenced by the plugin ABI.

## 1. Document Layout

JSON payloads emitted by `repo2mmd graph --format json` follow this structure:

```json
{
  "schema_version": 1,
  "graph": {
    "nodes": [ { /* r2m_node */ }, ... ],
    "edges": [ { /* r2m_edge */ }, ... ]
  },
  "manifest": { /* graph_manifest */ },
  "diagnostics": [ { /* diagnostic */ }, ... ]
}
```

Future schema revisions increment `schema_version` and preserve backward compatibility whenever possible. Consumers must check the version before processing.

## 2. Nodes (`r2m_node`)

| Field | Type | Description |
| --- | --- | --- |
| `id` | `string` | Hex-encoded 64-bit ID (xxHash64 of `fqname|kind|file|range`). |
| `lang` | `string` | Enum: `zig`, `c`, `ts`, or future language identifiers. |
| `kind` | `string` | Enum: `module`, `file`, `type`, `func`, `var`. |
| `name` | `string` | Short display name. |
| `fqname` | `string` | Fully-qualified name (language-specific). |
| `file` | `string` | Repository-relative POSIX path. |
| `range` | `object` | `{ "l0": uint32, "c0": uint32, "l1": uint32, "c1": uint32 }` (1-based). |
| `signature` | `string|null` | Optional function/type signature. |
| `visibility` | `string` | `public`, `private`, or `package`. |
| `origin_plugin` | `string` | Plugin identifier (`zig`, `c`, `ts`, ...). |
| `module_id` | `string|null` | Module/group identifier derived during discovery. |
| `tags` | `array[string]` | Free-form grouping hints (e.g., `"scope:dir:src/auth"`). |

## 3. Edges (`r2m_edge`)

| Field | Type | Description |
| --- | --- | --- |
| `src` | `string` | Node ID of the source. |
| `dst` | `string` | Node ID of the destination (may be `"0"` when unresolved). |
| `rel` | `string` | Enum: `imports`, `includes`, `calls`, `contains`, `extends`, `implements`. |
| `certainty` | `string` | Enum: `static`, `indirect`, `dynamic`, `comptime`, `unknown`. |
| `certainty_reason` | `string|null` | Human-readable explanation of the certainty label. |
| `evidence_paths` | `array[string]` | File paths containing evidence (optional). |
| `evidence_lines` | `array[uint32]` | Line numbers parallel to `evidence_paths`. |
| `diagnostics` | `array[diagnostic_ref]` | Diagnostic references associated with this edge. |

`diagnostic_ref` objects contain `{ "id": string }` pointing into the diagnostics table.

## 4. Manifest (`graph_manifest`)

| Field | Type | Description |
| --- | --- | --- |
| `generated_at` | `string` | ISO-8601 timestamp (UTC). |
| `generator_version` | `string` | repo2mmd semantic version. |
| `graph_type` | `string` | Requested graph type (`deps`, `call`, `class`, `include`). |
| `input_root` | `string` | Absolute path of analysed root (normalised). |
| `schema_version` | `uint32` | Mirrors top-level `schema_version`. |
| `node_count` | `uint32` | Number of nodes emitted. |
| `edge_count` | `uint32` | Number of edges emitted. |
| `unresolved_refs` | `uint32` | Count of edges with `dst == "0"`. |
| `cache_hits` | `uint32` | Number of SourceUnits served from cache. |
| `cache_misses` | `uint32` | Number of SourceUnits parsed cold. |
| `plugins_used` | `array[plugin_summary]` | Active plugin versions. |
| `cli_args` | `array[string]` | Normalised CLI arguments (excluding secrets). |

`plugin_summary` objects contain `{ "id": string, "version": string, "schema_min": uint32, "schema_max": uint32 }`.

## 5. Diagnostics (`diagnostic`)

| Field | Type | Description |
| --- | --- | --- |
| `id` | `string` | Stable identifier for correlation. |
| `severity` | `string` | Enum: `info`, `warn`, `error`. |
| `code` | `string` | Machine-readable code (`UNRESOLVED_REF`, `PARSE_ERROR`, ...). |
| `message` | `string` | Human-readable description. |
| `file` | `string|null` | Path associated with the issue. |
| `range` | `object|null` | Same format as node range. |
| `plugin` | `string|null` | Originating plugin ID (if applicable). |

## 6. Example Payload

```json
{
  "schema_version": 1,
  "graph": {
    "nodes": [
      {
        "id": "8f6c88c9b96a0f21",
        "lang": "ts",
        "kind": "func",
        "name": "handler",
        "fqname": "api/users::handler",
        "file": "src/api/users.ts",
        "range": { "l0": 12, "c0": 1, "l1": 34, "c1": 2 },
        "signature": "(request: Request) => Promise<Response>",
        "visibility": "public",
        "origin_plugin": "ts",
        "module_id": "module:api",
        "tags": ["scope:dir:src/api"]
      }
    ],
    "edges": [
      {
        "src": "8f6c88c9b96a0f21",
        "dst": "9b2d4bfed010ff5e",
        "rel": "calls",
        "certainty": "static",
        "certainty_reason": "Direct identifier reference",
        "evidence_paths": ["src/api/users.ts"],
        "evidence_lines": [18],
        "diagnostics": []
      }
    ]
  },
  "manifest": {
    "generated_at": "2025-10-06T18:45:12Z",
    "generator_version": "0.1.0-alpha",
    "graph_type": "call",
    "input_root": "/home/user/repo",
    "schema_version": 1,
    "node_count": 42,
    "edge_count": 67,
    "unresolved_refs": 3,
    "cache_hits": 120,
    "cache_misses": 14,
    "plugins_used": [
      { "id": "ts", "version": "0.1.0", "schema_min": 1, "schema_max": 1 },
      { "id": "c", "version": "0.1.0", "schema_min": 1, "schema_max": 1 }
    ],
    "cli_args": ["graph", "--type", "call", "--lang", "ts,c"]
  },
  "diagnostics": [
    {
      "id": "diag-unresolved-1",
      "severity": "warn",
      "code": "UNRESOLVED_REF",
      "message": "Unable to resolve symbol auth::hash",
      "file": "src/auth/index.ts",
      "range": { "l0": 45, "c0": 5, "l1": 45, "c1": 18 },
      "plugin": "ts"
    }
  ]
}
```

## 7. Versioning Policy

- Schema changes increment the unsigned integer `schema_version`.
- Breaking changes (field removals or type shifts) require bumping to the next integer and updating plugin `schema_min/schema_max` ranges.
- Additive changes (new optional fields) may be released within the same version but must remain backwards compatible.
- The JSON schema is maintained in lockstep with the C headers (`include/ir.h`) and mirrored in integration tests.

