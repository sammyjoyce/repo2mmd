#ifndef REPO2MMD_FRONTEND_H
#define REPO2MMD_FRONTEND_H

#include "ir.h"

#ifdef __cplusplus
extern "C" {
#endif

// Plugin ABI version
#define R2M_FRONTEND_API_VERSION 1

// Forward compatibility padding size
#define R2M_RESERVED_PAD 3

// Path view for file operations
typedef struct {
  const char *data;
  size_t len;
} r2m_path_view_t;

// Status codes for plugin operations
typedef enum {
  R2M_STATUS_OK = 0,
  R2M_STATUS_SKIP = 1,
  R2M_STATUS_RECOVERABLE_ERROR = 2,
  R2M_STATUS_FATAL = 3,
} r2m_status_t;

// Plugin capability flags
typedef enum {
  R2M_CAP_REQUIRES_CONTENT = 1 << 0,
  R2M_CAP_NEEDS_PROJECT_GRAPH = 1 << 1,
  R2M_CAP_SUPPORTS_INCREMENTAL = 1 << 2,
  R2M_CAP_CAN_HANDLE_LARGE_FILES = 1 << 3,
} r2m_capability_t;

// Typed arena allocator interface
typedef struct {
  void *state;
  void *(*alloc)(void *state, size_t align, size_t size);
  void (*reset)(void *state);
  uint32_t max_bytes;
  uint32_t used_bytes;
  uint32_t abi_version;
  uint32_t struct_size;
  void *reserved[R2M_RESERVED_PAD];
} r2m_arena_t;

// Host service table for plugin operations
typedef struct {
  // Logging service
  void (*log)(void *state, r2m_severity_t severity, const char *message);
  void *log_state;

  // File I/O service
  bool (*read_file)(void *state, const r2m_path_view_t *path,
                    r2m_path_view_t *content);
  void (*free_content)(void *state, r2m_path_view_t *content);
  void *io_state;

  // Cache service
  bool (*cache_get)(void *state, const r2m_path_view_t *path, const void **data,
                    size_t *size);
  bool (*cache_put)(void *state, const r2m_path_view_t *path, const void *data,
                    size_t size);
  void *cache_state;

  uint32_t abi_version;
  uint32_t struct_size;
  void *reserved[R2M_RESERVED_PAD];
} r2m_frontend_host_v1_t;

// Parse request structure
typedef struct {
  // Basic file information
  r2m_path_view_t file_path;
  r2m_path_view_t content;

  // Project context
  r2m_path_view_t project_root;
  const void *compilation_database;  // Opaque handle for compile_commands.json
  r2m_path_view_t *cli_args;
  size_t cli_arg_count;

  // Memory and services
  r2m_arena_t *arena;
  const r2m_frontend_host_v1_t *host;
  uint32_t max_bytes;
  uint32_t diagnostic_budget;

  // Parse flags
  uint32_t parse_flags;  // Bitmask of parse options

  uint32_t abi_version;
  uint32_t struct_size;
  void *reserved[R2M_RESERVED_PAD];
} r2m_parse_request_t;

// Parse response structure
typedef struct {
  r2m_node_t *nodes;
  size_t node_count;
  r2m_edge_t *edges;
  size_t edge_count;
  r2m_diagnostic_t *diagnostics;
  size_t diagnostic_count;

  r2m_status_t status;
  const char *error_message;  // Arena-backed, only valid if status != OK

  uint32_t abi_version;
  uint32_t struct_size;
  void *reserved[R2M_RESERVED_PAD];
} r2m_parse_response_t;

// Plugin initialization context
typedef struct {
  const r2m_frontend_host_v1_t *host;
  r2m_path_view_t plugin_path;
  r2m_path_view_t *config_args;
  size_t config_arg_count;

  uint32_t abi_version;
  uint32_t struct_size;
  void *reserved[R2M_RESERVED_PAD];
} r2m_init_context_t;

// Plugin frontend interface
typedef struct {
  // ABI metadata
  uint32_t abi_version;
  uint32_t struct_size;
  const char *id;
  uint32_t api_version;
  uint32_t schema_min;
  uint32_t schema_max;
  uint64_t capabilities;  // Bitmask of r2m_capability_t

  // Plugin state
  void *plugin_state;

  // Core plugin functions
  r2m_status_t (*init)(const r2m_init_context_t *context);
  bool (*wants_file)(const r2m_path_view_t *path);
  r2m_status_t (*parse_file)(const r2m_parse_request_t *request,
                             r2m_parse_response_t *response);

  // Optional functions (can be NULL)
  r2m_status_t (*post_resolve)(const r2m_graph_t *graph);
  r2m_status_t (*collect_manifest)(r2m_plugin_summary_t *summary);
  r2m_status_t (*teardown)(void);

  // Legacy compatibility (deprecated)
  bool (*shutdown)(void);  // Use teardown() instead

  void *reserved[R2M_RESERVED_PAD];
} r2m_frontend_v1_t;

// Plugin entry point
extern const r2m_frontend_v1_t *r2m_get_frontend_v1(void);

#ifdef __cplusplus
}
#endif

#endif  // REPO2MMD_FRONTEND_H