# JSON Schema Documentation

This document describes the JSON schema emitted by `repo2mmd` when using the `--format json` option.

## Schema Version

Current schema version: `1`

## Root Structure

```json
{
  "schema_version": 1,
  "graph_type": "Deps",
  "node_count": 3,
  "edge_count": 2,
  "nodes": [...],
  "edges": [...]
}
```

### Fields

- `schema_version` (integer): The version of the JSON schema
- `graph_type` (string): The type of graph analysis performed (currently "Deps")
- `node_count` (integer): Number of nodes in the graph
- `edge_count` (integer): Number of edges in the graph
- `nodes` (array): Array of node objects
- `edges` (array): Array of edge objects

## Node Object

```json
{
  "id": "23d70bab5e55b890",
  "lang": "zig",
  "kind": "module",
  "name": "auth.zig",
  "visibility": "public"
}
```

### Fields

- `id` (string): Unique identifier for the node (typically a hash)
- `lang` (string): Programming language ("zig", "c", "ts", etc.)
- `kind` (string): Type of node ("module", "function", "type", "file", "var")
- `name` (string): Display name of the node
- `visibility` (string): Visibility level ("public", "private", "internal")

## Edge Object

```json
{
  "src": "951a84edb4c1f6c5",
  "dst": "23d70bab5e55b890",
  "rel": "imports",
  "certainty": "static"
}
```

### Fields

- `src` (string): ID of the source node
- `dst` (string): ID of the destination node
- `rel` (string): Relationship type ("imports", "includes", "calls", "contains", "extends", "implements")
- `certainty` (string): Certainty level ("static", "indirect", "dynamic", "comptime")

## Relationship Types

- `imports`: Import relationship (e.g., `@import` in Zig)
- `includes`: Include relationship (e.g., `#include` in C)
- `calls`: Function call relationship
- `contains`: Containment relationship (e.g., module contains function)
- `extends`: Inheritance relationship
- `implements`: Interface implementation relationship

## Certainty Levels

- `static`: Statically determined relationship
- `indirect`: Indirect relationship (e.g., through function pointers)
- `dynamic`: Runtime-determined relationship
- `comptime`: Compile-time determined relationship

## Node Kinds

- `module`: Module or file-level unit
- `function`: Function or method
- `type`: Type definition (struct, class, enum)
- `file`: File node
- `var`: Variable or constant

## Languages

- `zig`: Zig programming language
- `c`: C programming language
- `ts`: TypeScript programming language
- Other language identifiers may be added as support is expanded

## Example Complete Output

```json
{
  "schema_version": 1,
  "graph_type": "Deps",
  "node_count": 3,
  "edge_count": 2,
  "nodes": [
    {
      "id": "23d70bab5e55b890",
      "lang": "zig",
      "kind": "module",
      "name": "auth.zig",
      "visibility": "public"
    },
    {
      "id": "038f326aa85a9003",
      "lang": "zig",
      "kind": "module",
      "name": "database.zig",
      "visibility": "public"
    },
    {
      "id": "951a84edb4c1f6c5",
      "lang": "zig",
      "kind": "module",
      "name": "main.zig",
      "visibility": "public"
    }
  ],
  "edges": [
    {
      "src": "951a84edb4c1f6c5",
      "dst": "23d70bab5e55b890",
      "rel": "imports",
      "certainty": "static"
    },
    {
      "src": "951a84edb4c1f6c5",
      "dst": "038f326aa85a9003",
      "rel": "imports",
      "certainty": "static"
    }
  ]
}
```

## Deterministic Output

The JSON output is deterministic:
- Nodes are sorted by `id` alphabetically
- Edges are sorted by `(src, dst, rel)` tuple
- This ensures consistent output across runs for hash stability

## Schema Evolution

Future versions may add:
- Additional node fields (signatures, documentation, etc.)
- More granular certainty levels
- Additional relationship types
- Metadata fields (timestamps, versions, etc.)

Backward compatibility will be maintained as much as possible, with `schema_version` indicating breaking changes.