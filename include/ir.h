#ifndef REPO2MMD_IR_H
#define REPO2MMD_IR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

// Schema versioning
#define R2M_SCHEMA_VERSION 1

// String view type for efficient string handling
typedef struct {
  const char *data;
  size_t len;
} r2m_string_view_t;

// Position type (1-based)
typedef struct {
  uint32_t line;
  uint32_t column;
} r2m_position_t;

// Range type
typedef struct {
  r2m_position_t start;
  r2m_position_t end;
} r2m_range_t;

// Node kinds
typedef enum {
  R2M_NODE_MODULE,
  R2M_NODE_FILE,
  R2M_NODE_TYPE,
  R2M_NODE_FUNC,
  R2M_NODE_VAR,
} r2m_node_kind_t;

// Edge relationships
typedef enum {
  R2M_EDGE_IMPORTS,
  R2M_EDGE_INCLUDES,
  R2M_EDGE_CALLS,
  R2M_EDGE_CONTAINS,
  R2M_EDGE_EXTENDS,
  R2M_EDGE_IMPLEMENTS,
} r2m_edge_rel_t;

// Certainty levels
typedef enum {
  R2M_CERT_STATIC,
  R2M_CERT_INDIRECT,
  R2M_CERT_DYNAMIC,
  R2M_CERT_COMPTIME,
  R2M_CERT_UNKNOWN,
} r2m_certainty_t;

// Visibility levels
typedef enum {
  R2M_VIS_PUBLIC,
  R2M_VIS_PRIVATE,
  R2M_VIS_PACKAGE,
} r2m_visibility_t;

// Diagnostic severity
typedef enum {
  R2M_SEV_INFO,
  R2M_SEV_WARN,
  R2M_SEV_ERROR,
} r2m_severity_t;

// Diagnostic reference
typedef struct {
  r2m_string_view_t id;
} r2m_diagnostic_ref_t;

// Node structure
typedef struct {
  r2m_string_view_t id;
  r2m_string_view_t lang;
  r2m_node_kind_t kind;
  r2m_string_view_t name;
  r2m_string_view_t fqname;
  r2m_string_view_t file;
  r2m_range_t range;
  r2m_string_view_t signature;  // Optional, empty if not present
  r2m_visibility_t visibility;
  r2m_string_view_t origin_plugin;
  r2m_string_view_t module_id;  // Optional, empty if not present
  r2m_string_view_t *tags;      // Array of tags
  size_t tag_count;
} r2m_node_t;

// Edge structure
typedef struct {
  r2m_string_view_t src;
  r2m_string_view_t dst;
  r2m_edge_rel_t rel;
  r2m_certainty_t certainty;
  r2m_string_view_t certainty_reason;  // Optional, empty if not present
  r2m_string_view_t *evidence_paths;   // Array of evidence paths
  size_t evidence_path_count;
  uint32_t *evidence_lines;  // Array of evidence lines
  size_t evidence_line_count;
  r2m_diagnostic_ref_t *diagnostics;  // Array of diagnostic references
  size_t diagnostic_count;
} r2m_edge_t;

// Full diagnostic structure
typedef struct {
  r2m_string_view_t id;
  r2m_severity_t severity;
  r2m_string_view_t code;
  r2m_string_view_t message;
  r2m_string_view_t file;    // Optional, empty if not present
  r2m_range_t range;         // Valid only if file is present
  r2m_string_view_t plugin;  // Optional, empty if not present
} r2m_diagnostic_t;

// Plugin summary
typedef struct {
  r2m_string_view_t id;
  r2m_string_view_t version;
  uint32_t schema_min;
  uint32_t schema_max;
} r2m_plugin_summary_t;

// Graph manifest
typedef struct {
  r2m_string_view_t generated_at;
  r2m_string_view_t generator_version;
  r2m_string_view_t graph_type;
  r2m_string_view_t input_root;
  uint32_t schema_version;
  uint32_t node_count;
  uint32_t edge_count;
  uint32_t resolved_refs;
  uint32_t unresolved_refs;
  float resolution_rate;
  uint32_t cache_hits;
  uint32_t cache_misses;
  r2m_plugin_summary_t *plugins_used;
  size_t plugin_count;
  r2m_string_view_t *cli_args;
  size_t cli_arg_count;
} r2m_graph_manifest_t;

// Graph structure
typedef struct {
  r2m_node_t *nodes;
  size_t node_count;
  r2m_edge_t *edges;
  size_t edge_count;
} r2m_graph_t;

// Complete IR structure
typedef struct {
  uint32_t schema_version;
  r2m_graph_t graph;
  r2m_graph_manifest_t manifest;
  r2m_diagnostic_t *diagnostics;
  size_t diagnostic_count;
} r2m_ir_t;

// Helper functions for string view operations
static inline bool r2m_string_view_equals(r2m_string_view_t a,
                                          r2m_string_view_t b) {
  return a.len == b.len && (a.len == 0 || memcmp(a.data, b.data, a.len) == 0);
}

static inline r2m_string_view_t r2m_string_view_from_cstr(const char *cstr) {
  if (cstr == NULL)
    return (r2m_string_view_t){.data = NULL, .len = 0};
  return (r2m_string_view_t){.data = cstr, .len = strlen(cstr)};
}

// Helper functions for enum to string conversion
const char *r2m_node_kind_to_string(r2m_node_kind_t kind);
const char *r2m_edge_rel_to_string(r2m_edge_rel_t rel);
const char *r2m_certainty_to_string(r2m_certainty_t certainty);
const char *r2m_visibility_to_string(r2m_visibility_t visibility);
const char *r2m_severity_to_string(r2m_severity_t severity);

#ifdef __cplusplus
}
#endif

#endif  // REPO2MMD_IR_H
