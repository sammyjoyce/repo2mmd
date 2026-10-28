#include <stdalign.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../include/frontend.h"
#include "../common/common.h"
#include "../common/abi.h"

// Simple arena allocator for testing
typedef struct {
  char *buffer;
  size_t capacity;
  size_t offset;
} dummy_arena_t;

static void *arena_alloc(void *state, size_t align, size_t size) {
  dummy_arena_t *arena = (dummy_arena_t *)state;
  // Align the offset
  size_t aligned_offset = (arena->offset + align - 1) & ~(align - 1);
  if (aligned_offset + size > arena->capacity) {
    return NULL;
  }
  void *ptr = arena->buffer + aligned_offset;
  arena->offset = aligned_offset + size;
  return ptr;
}

static void arena_reset(void *state) {
  dummy_arena_t *arena = (dummy_arena_t *)state;
  arena->offset = 0;
}

// Check if plugin wants to handle a file
static bool wants_file(const r2m_path_view_t *path) {
  // Accept all files for testing
  (void)path;  // Suppress unused parameter warning
  return true;
}

// Plugin initialization
static r2m_status_t init(const r2m_init_context_t *context) {
  return r2m_plugin_noop_init(context);
}

// Parse a file and return dummy results
static r2m_status_t parse_file(const r2m_parse_request_t *request,
                               r2m_parse_response_t *response) {
  if (!request || !response || !request->arena) {
    return R2M_STATUS_FATAL;
  }

  // Initialize response structure
  memset(response, 0, sizeof(r2m_parse_response_t));
  response->abi_version = R2M_FRONTEND_API_VERSION;
  response->struct_size = sizeof(r2m_parse_response_t);

  // Set up a simple arena buffer
  static dummy_arena_t arena = {0};
  static char arena_buffer[4096];
  arena.buffer = arena_buffer;
  arena.capacity = sizeof(arena_buffer);
  arena.offset = 0;

  // Update arena interface
  request->arena->state = &arena;
  request->arena->alloc = arena_alloc;
  request->arena->reset = arena_reset;

  // Create one dummy node per file
  r2m_node_t *node = (r2m_node_t *)arena_alloc(&arena, alignof(r2m_node_t),
                                               sizeof(r2m_node_t));
  if (!node) {
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to allocate node";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  // Initialize node with file information
  memset(node, 0, sizeof(r2m_node_t));

  // Create a simple ID based on file path
  char node_id[256];
  snprintf(node_id, sizeof(node_id), "dummy_node_%.*s",
           (int)request->file_path.len, request->file_path.data);

  node->id.data = arena_alloc(&arena, alignof(char), strlen(node_id) + 1);
  if (node->id.data) {
    strcpy((char *)node->id.data, node_id);
    node->id.len = strlen(node_id);
  }

  node->lang = r2m_string_view_from_cstr("dummy");
  node->kind = R2M_NODE_FILE;

  // Convert path_view to string_view for assignment
  node->name.data = request->file_path.data;
  node->name.len = request->file_path.len;
  node->fqname.data = request->file_path.data;
  node->fqname.len = request->file_path.len;
  node->file.data = request->file_path.data;
  node->file.len = request->file_path.len;

  node->range.start.line = 1;
  node->range.start.column = 1;
  node->range.end.line = 1;
  node->range.end.column = 1;
  node->visibility = R2M_VIS_PUBLIC;
  node->origin_plugin = r2m_string_view_from_cstr("dummy");

  // Create edges for synthetic Zig repo test
  r2m_edge_t *edges = NULL;
  size_t edge_count = 0;

  // Check if this is main.zig in synthetic repo
  if (request->file_path.len >= 8 &&
      strncmp(request->file_path.data + request->file_path.len - 8, "main.zig",
              8) == 0) {
    // Create 2 edges for auth.zig and database.zig imports
    edges = (r2m_edge_t *)arena_alloc(&arena, alignof(r2m_edge_t),
                                      2 * sizeof(r2m_edge_t));
    if (edges) {
      // Edge to auth.zig
      r2m_edge_t *auth_edge = &edges[0];
      memset(auth_edge, 0, sizeof(r2m_edge_t));
      auth_edge->src.data = node->id.data;
      auth_edge->src.len = node->id.len;
      auth_edge->dst.data = arena_alloc(&arena, alignof(char), 32);
      if (auth_edge->dst.data) {
        strcpy((char *)auth_edge->dst.data, "dummy_module_auth.zig");
        auth_edge->dst.len = strlen("dummy_module_auth.zig");
      }
      auth_edge->rel = R2M_EDGE_IMPORTS;
      auth_edge->certainty = R2M_CERT_STATIC;

      // Edge to database.zig
      r2m_edge_t *db_edge = &edges[1];
      memset(db_edge, 0, sizeof(r2m_edge_t));
      db_edge->src.data = node->id.data;
      db_edge->src.len = node->id.len;
      db_edge->dst.data = arena_alloc(&arena, alignof(char), 32);
      if (db_edge->dst.data) {
        strcpy((char *)db_edge->dst.data, "dummy_module_database.zig");
        db_edge->dst.len = strlen("dummy_module_database.zig");
      }
      db_edge->rel = R2M_EDGE_IMPORTS;
      db_edge->certainty = R2M_CERT_STATIC;

      edge_count = 2;
    }
  }

  // Set response
  response->nodes = node;
  response->node_count = 1;
  response->edges = edges;
  response->edge_count = edge_count;
  response->diagnostics = NULL;
  response->diagnostic_count = 0;
  response->status = R2M_STATUS_OK;
  response->error_message = NULL;

  return R2M_STATUS_OK;
}

// Collect plugin manifest information
static r2m_status_t collect_manifest(r2m_plugin_summary_t *summary) {
  if (!summary) {
    return R2M_STATUS_FATAL;
  }

  summary->id = r2m_string_view_from_cstr("dummy");
  summary->version = r2m_string_view_from_cstr("0.1.0");
  summary->schema_min = R2M_SCHEMA_VERSION;
  summary->schema_max = R2M_SCHEMA_VERSION;

  return R2M_STATUS_OK;
}

// Plugin teardown
static r2m_status_t teardown(void) {
  return r2m_plugin_noop_teardown();
}

// Legacy shutdown for compatibility
static bool shutdown(void) {
  return r2m_plugin_noop_shutdown();
}

// Plugin interface definition
static const r2m_frontend_v1_t dummy_frontend = {
    .abi_version = R2M_FRONTEND_API_VERSION,
    .struct_size = sizeof(r2m_frontend_v1_t),
    .id = "dummy",
    .api_version = R2M_FRONTEND_API_VERSION,
    .schema_min = R2M_SCHEMA_VERSION,
    .schema_max = R2M_SCHEMA_VERSION,
    .capabilities = R2M_CAP_REQUIRES_CONTENT,
    .plugin_state = NULL,

    .init = init,
    .wants_file = wants_file,
    .parse_file = parse_file,
    .post_resolve = NULL,  // Optional
    .collect_manifest = collect_manifest,
    .teardown = teardown,
    .shutdown = shutdown,  // Legacy compatibility

    .reserved = {0},
};

// Plugin entry point
extern const r2m_frontend_v1_t *r2m_get_frontend_v1(void) {
  return &dummy_frontend;
}
