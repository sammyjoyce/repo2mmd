#include <pthread.h>
#include <stdalign.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../include/frontend.h"
#include "tree_sitter/api.h"

// External declaration for the tree-sitter zig language function
extern TSLanguage *tree_sitter_zig(void);

typedef struct {
  r2m_node_t *items;
  size_t count;
  size_t capacity;
} node_buffer_t;

typedef struct {
  r2m_edge_t *items;
  size_t count;
  size_t capacity;
} edge_buffer_t;

// Thread-local context for tree-sitter operations
typedef struct {
  TSParser *parser;
  TSLanguage *zig_language;
  bool initialized;
} thread_local_zig_context_t;

static _Thread_local thread_local_zig_context_t tl_context = {0};

// Initialize thread-local context
static r2m_status_t init_thread_local_context(void) {
  if (tl_context.initialized) {
    return R2M_STATUS_OK;
  }

  tl_context.parser = ts_parser_new();
  if (!tl_context.parser) {
    return R2M_STATUS_FATAL;
  }

  tl_context.zig_language = tree_sitter_zig();
  if (!tl_context.zig_language) {
    ts_parser_delete(tl_context.parser);
    tl_context.parser = NULL;
    return R2M_STATUS_FATAL;
  }

  ts_parser_set_language(tl_context.parser, tl_context.zig_language);
  tl_context.initialized = true;

  return R2M_STATUS_OK;
}

// Cleanup thread-local context
static void cleanup_thread_local_context(void) {
  if (tl_context.parser) {
    ts_parser_delete(tl_context.parser);
    tl_context.parser = NULL;
  }
  tl_context.zig_language = NULL;
  tl_context.initialized = false;
}

static bool ensure_node_capacity(node_buffer_t *buffer, size_t required) {
  if (required <= buffer->capacity) {
    return true;
  }

  size_t new_capacity = buffer->capacity == 0 ? required : buffer->capacity;
  while (new_capacity < required) {
    new_capacity *= 2;
  }

  r2m_node_t *items = realloc(buffer->items, new_capacity * sizeof(r2m_node_t));
  if (!items) {
    return false;
  }

  buffer->items = items;
  buffer->capacity = new_capacity;
  return true;
}

static bool ensure_edge_capacity(edge_buffer_t *buffer, size_t required) {
  if (required <= buffer->capacity) {
    return true;
  }

  size_t new_capacity = buffer->capacity == 0 ? required : buffer->capacity;
  while (new_capacity < required) {
    new_capacity *= 2;
  }

  r2m_edge_t *items = realloc(buffer->items, new_capacity * sizeof(r2m_edge_t));
  if (!items) {
    return false;
  }

  buffer->items = items;
  buffer->capacity = new_capacity;
  return true;
}

static void free_node_buffer(node_buffer_t *buffer) {
  free(buffer->items);
  buffer->items = NULL;
  buffer->count = 0;
  buffer->capacity = 0;
}

static void free_edge_buffer(edge_buffer_t *buffer) {
  free(buffer->items);
  buffer->items = NULL;
  buffer->count = 0;
  buffer->capacity = 0;
}

static size_t resolve_import_path(const r2m_parse_request_t *request,
                                  const char *import_path,
                                  char *buffer, size_t buffer_size) {
  if (!import_path || !buffer || buffer_size == 0) {
    return 0;
  }

  if (import_path[0] == '@') {
    return 0;
  }

  const char *current = request->file_path.data;
  size_t current_len = request->file_path.len;

  size_t prefix_len = current_len;
  while (prefix_len > 0 && current[prefix_len - 1] != '/') {
    prefix_len--;
  }

  size_t out_len = 0;
  if (prefix_len > 0) {
    if (prefix_len >= buffer_size) {
      return 0;
    }
    memcpy(buffer, current, prefix_len);
    out_len = prefix_len;
  }

  char segment[256];
  const char *cursor = import_path;
  while (*cursor) {
    const char *next = strchr(cursor, '/');
    size_t seg_len = next ? (size_t)(next - cursor) : strlen(cursor);

    if (seg_len == 0 || (seg_len == 1 && cursor[0] == '.')) {
      // skip
    } else if (seg_len == 2 && cursor[0] == '.' && cursor[1] == '.') {
      if (out_len > 0) {
        if (buffer[out_len - 1] == '/') {
          out_len--;
        }
        while (out_len > 0 && buffer[out_len - 1] != '/') {
          out_len--;
        }
      }
    } else {
      if (out_len > 0 && buffer[out_len - 1] != '/') {
        if (out_len + 1 >= buffer_size) {
          return 0;
        }
        buffer[out_len++] = '/';
      }
      if (seg_len >= sizeof(segment)) {
        return 0;
      }
      memcpy(segment, cursor, seg_len);
      segment[seg_len] = '\0';
      if (out_len + seg_len >= buffer_size) {
        return 0;
      }
      memcpy(buffer + out_len, segment, seg_len);
      out_len += seg_len;
    }

    if (!next) {
      break;
    }
    cursor = next + 1;
  }

  return out_len;
}

// String utilities
static bool string_view_ends_with(const r2m_path_view_t *view, const char *suffix) {
  if (!view || !suffix || !view->data) {
    return false;
  }
  size_t suffix_len = strlen(suffix);
  if (suffix_len > view->len) {
    return false;
  }
  return strncmp(view->data + (view->len - suffix_len), suffix, suffix_len) == 0;
}

// Check if plugin wants to handle a file
static bool wants_file(const r2m_path_view_t *path) {
  if (!path || !path->data) {
    return false;
  }

  // Check for .zig extension
  return string_view_ends_with(path, ".zig");
}

// Plugin initialization
static r2m_status_t init(const r2m_init_context_t *context) {
  if (!context) {
    return R2M_STATUS_FATAL;
  }

  // Initialize thread-local tree-sitter context
  return init_thread_local_context();
}

// Convert TSNode to string view
static r2m_string_view_t ts_node_to_string_view(TSNode node,
                                                const char *source_code) {
  r2m_string_view_t result = {0};
  if (!source_code) {
    return result;
  }

  uint32_t start_byte = ts_node_start_byte(node);
  uint32_t end_byte = ts_node_end_byte(node);

  result.data = source_code + start_byte;
  result.len = end_byte - start_byte;

  return result;
}

// Convert TSPoint to r2m position
static r2m_position_t ts_point_to_position(TSPoint point) {
  r2m_position_t result = {
      .line = point.row + 1,      // Tree-sitter uses 0-based lines
      .column = point.column + 1  // Tree-sitter uses 0-based columns
  };
  return result;
}

// Get node text as string view
static r2m_string_view_t get_node_text(TSNode node, const char *source_code) {
  return ts_node_to_string_view(node, source_code);
}

static bool is_node_type(TSNode node, const char *type) {
  const char *node_type = ts_node_type(node);
  return strcmp(node_type, type) == 0;
}

static TSNode find_descendant_by_type(TSNode node, const char *type,
                                      uint32_t max_depth) {
  if (ts_node_is_null(node)) {
    TSNode null_node = {0};
    return null_node;
  }

  if (is_node_type(node, type)) {
    return node;
  }

  if (max_depth == 0) {
    TSNode null_node = {0};
    return null_node;
  }

  uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(node, i);
    TSNode result = find_descendant_by_type(child, type, max_depth - 1);
    if (!ts_node_is_null(result)) {
      return result;
    }
  }

  TSNode null_node = {0};
  return null_node;
}

static bool is_struct_container(TSNode node) {
  uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(node, i);
    const char *child_type = ts_node_type(child);
    if (strcmp(child_type, "struct") == 0 ||
        strcmp(child_type, "KEYWORD_struct") == 0) {
      return true;
    }
    if (strcmp(child_type, "ContainerDeclType") == 0) {
      TSNode keyword = find_descendant_by_type(child, "struct", 2);
      if (ts_node_is_null(keyword)) {
        keyword = find_descendant_by_type(child, "KEYWORD_struct", 2);
      }
      if (!ts_node_is_null(keyword)) {
        return true;
      }
    }
  }
  return false;
}

typedef struct {
  const r2m_parse_request_t *request;
  r2m_node_t *file_node;
  const char *source_code;
  edge_buffer_t *edges;
} import_context_t;

static bool append_import_edge(const import_context_t *ctx,
                               const char *import_path,
                               size_t path_len,
                               uint32_t evidence_line) {
  if (!ctx || !ctx->file_node || !ctx->edges || path_len == 0 ||
      path_len >= 512) {
    return true;
  }

  if (!ensure_edge_capacity(ctx->edges, ctx->edges->count + 1)) {
    return false;
  }

  char import_path_buffer[512];
  memcpy(import_path_buffer, import_path, path_len);
  import_path_buffer[path_len] = '\0';

  r2m_edge_t *edge = &ctx->edges->items[ctx->edges->count];
  memset(edge, 0, sizeof(r2m_edge_t));

  if (ctx->file_node->id.len > 0) {
    edge->src.data = ctx->request->arena->alloc(ctx->request->arena->state,
                                                alignof(char),
                                                ctx->file_node->id.len + 1);
    if (!edge->src.data) {
      return false;
    }
    strcpy((char *)edge->src.data, (const char *)ctx->file_node->id.data);
    edge->src.len = ctx->file_node->id.len;
  }

  // Zig resolves "*.zig" and "*.zon" imports relative to the importing file; any other
  // string names a module ("std", "builtin", "root", or one from build.zig).
  const bool is_file_import =
      path_len > 4 && (strcmp(import_path_buffer + path_len - 4, ".zig") == 0 ||
                       strcmp(import_path_buffer + path_len - 4, ".zon") == 0);

  const char *path_for_id = import_path_buffer;
  char resolved_path[512];
  if (is_file_import) {
    size_t resolved_len = resolve_import_path(
        ctx->request, import_path_buffer, resolved_path, sizeof(resolved_path));
    if (resolved_len > 0 && resolved_len < sizeof(resolved_path)) {
      resolved_path[resolved_len] = '\0';
      path_for_id = resolved_path;
    }
  }

  char target_id[512];
  snprintf(target_id, sizeof(target_id), "file_%s", path_for_id);

  size_t target_id_len = strlen(target_id);
  if (target_id_len > 0) {
    edge->dst.data = ctx->request->arena->alloc(ctx->request->arena->state,
                                               alignof(char), target_id_len + 1);
    if (!edge->dst.data) {
      return false;
    }
    strcpy((char *)edge->dst.data, target_id);
    edge->dst.len = target_id_len;
  }

  const bool is_toolchain_module =
      !is_file_import && (strcmp(import_path_buffer, "std") == 0 ||
                          strcmp(import_path_buffer, "builtin") == 0 ||
                          strcmp(import_path_buffer, "root") == 0);

  edge->rel = R2M_EDGE_IMPORTS;
  edge->certainty = is_toolchain_module ? R2M_CERT_COMPTIME : R2M_CERT_STATIC;

  r2m_arena_t *arena = ctx->request->arena;
  r2m_string_view_t *evidence_path = arena->alloc(
      arena->state, alignof(r2m_string_view_t), sizeof(r2m_string_view_t));
  uint32_t *evidence_line_slot =
      arena->alloc(arena->state, alignof(uint32_t), sizeof(uint32_t));
  if (!evidence_path || !evidence_line_slot) {
    return false;
  }
  evidence_path->data = ctx->request->file_path.data;
  evidence_path->len = ctx->request->file_path.len;
  *evidence_line_slot = evidence_line;
  edge->evidence_paths = evidence_path;
  edge->evidence_path_count = 1;
  edge->evidence_lines = evidence_line_slot;
  edge->evidence_line_count = 1;

  ctx->edges->count++;
  return true;
}

static bool extract_import_path(TSNode args_node,
                                const char *source_code,
                                char *buffer,
                                size_t buffer_size,
                                size_t *out_len) {
  if (buffer_size == 0 || !out_len) {
    return false;
  }

  uint32_t named_count = ts_node_named_child_count(args_node);
  if (named_count == 0) {
    return false;
  }

  TSNode first_arg = ts_node_named_child(args_node, 0);
  if (ts_node_is_null(first_arg)) {
    return false;
  }

  r2m_string_view_t arg_text = get_node_text(first_arg, source_code);
  if (arg_text.len < 2) {
    return false;
  }

  char quote_start = arg_text.data[0];
  char quote_end = arg_text.data[arg_text.len - 1];
  if (!((quote_start == '"' && quote_end == '"') ||
        (quote_start == '\'' && quote_end == '\''))) {
    return false;
  }

  size_t written = 0;
  for (size_t i = 1; i + 1 < arg_text.len; i++) {
    char c = arg_text.data[i];
    if (c == '\\' && i + 2 < arg_text.len) {
      char next = arg_text.data[i + 1];
      switch (next) {
        case '\\':
          c = '\\';
          i++;
          break;
        case '"':
          c = '"';
          i++;
          break;
        case '\'':
          c = '\'';
          i++;
          break;
        case 'n':
          c = '\n';
          i++;
          break;
        case 'r':
          c = '\r';
          i++;
          break;
        case 't':
          c = '\t';
          i++;
          break;
        default:
          // Leave as raw character, include the escape sequence
          break;
      }
    }

    if (written + 1 >= buffer_size) {
      return false;
    }

    buffer[written++] = c;
  }

  buffer[written] = '\0';
  *out_len = written;
  return true;
}

static TSNode find_child_by_type(TSNode node, const char *type, bool *found);
static r2m_string_view_t extract_identifier(TSNode node,
                                            const char *source_code);

static bool collect_import_edges_recursive(const import_context_t *ctx,
                                           TSNode node) {
  const char *node_type = ts_node_type(node);
  if (strcmp(node_type, "BUILTINIDENTIFIER") == 0) {
    r2m_string_view_t builtin = get_node_text(node, ctx->source_code);
    if (builtin.len == 7 && strncmp(builtin.data, "@import", 7) == 0) {
      TSNode call_node = ts_node_parent(node);
      bool found = false;
      TSNode args_node = {0};

      while (!ts_node_is_null(call_node)) {
        args_node = find_child_by_type(call_node, "FnCallArguments", &found);
        if (found) {
          break;
        }
        call_node = ts_node_parent(call_node);
      }

      if (found) {
        char import_path[512];
        size_t import_len = 0;
        if (extract_import_path(args_node, ctx->source_code, import_path,
                                sizeof(import_path), &import_len)) {
          const uint32_t line = ts_node_start_point(node).row + 1;
          if (!append_import_edge(ctx, import_path, import_len, line)) {
            return false;
          }
        }
      }
    }
  }

  uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(node, i);
    if (!collect_import_edges_recursive(ctx, child)) {
      return false;
    }
  }

  return true;
}

// Find child node of specific type
static TSNode find_child_by_type(TSNode node, const char *type, bool *found) {
  uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(node, i);
    if (is_node_type(child, type)) {
      *found = true;
      return child;
    }
  }
  *found = false;
  TSNode null_node = {0};
  return null_node;
}

static size_t collect_container_names(TSNode node, const char *source_code,
                                      r2m_string_view_t *out_names,
                                      size_t max_names) {
  if (!out_names || max_names == 0) {
    return 0;
  }

  size_t count = 0;
  TSNode current = ts_node_parent(node);
  while (!ts_node_is_null(current) && count < max_names) {
    const char *type = ts_node_type(current);
    if (strcmp(type, "VarDecl") == 0) {
      TSNode container = find_descendant_by_type(current, "ContainerDecl", 4);
      if (ts_node_is_null(container)) {
        container = find_descendant_by_type(current, "ContainerDeclType", 4);
      }

      if (!ts_node_is_null(container) && is_struct_container(container)) {
        r2m_string_view_t name = extract_identifier(current, source_code);
        if (name.len > 0) {
          out_names[count++] = name;
        }
      }
    }

    current = ts_node_parent(current);
  }

  return count;
}

static size_t write_container_prefix(const r2m_string_view_t *names,
                                     size_t count,
                                     char *buffer,
                                     size_t buffer_size) {
  if (!buffer || buffer_size == 0) {
    return 0;
  }

  size_t written = 0;
  for (size_t i = count; i > 0; i--) {
    r2m_string_view_t name = names[i - 1];
    if (name.len == 0) {
      continue;
    }

    if (written > 0) {
      if (written + 1 >= buffer_size) {
        return 0;
      }
      buffer[written++] = '_';
    }

    for (size_t j = 0; j < name.len; j++) {
      char c = name.data[j];
      bool keep = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9');
      if (!keep) {
        c = '_';
      }
      if (written + 1 >= buffer_size) {
        return 0;
      }
      buffer[written++] = c;
    }
  }

  if (written < buffer_size) {
    buffer[written] = '\0';
    return written;
  }

  return 0;
}

static bool set_function_fqname(r2m_node_t *func_node,
                                const r2m_parse_request_t *request,
                                const r2m_string_view_t *container_names,
                                size_t container_count,
                                r2m_string_view_t func_name) {
  if (container_count == 0) {
    func_node->fqname = func_name;
    return true;
  }

  size_t total_len = func_name.len + container_count;
  for (size_t i = 0; i < container_count; i++) {
    total_len += container_names[i].len;
  }

  char *fqname = request->arena->alloc(request->arena->state, alignof(char),
                                       total_len + 1);
  if (!fqname) {
    return false;
  }

  size_t offset = 0;
  for (size_t i = container_count; i > 0; i--) {
    r2m_string_view_t name = container_names[i - 1];
    memcpy(fqname + offset, name.data, name.len);
    offset += name.len;
    fqname[offset++] = '.';
  }

  memcpy(fqname + offset, func_name.data, func_name.len);
  offset += func_name.len;
  fqname[offset] = '\0';

  func_node->fqname.data = fqname;
  func_node->fqname.len = offset;
  return true;
}

// Extract identifier from various node types
static r2m_string_view_t extract_identifier(TSNode node,
                                            const char *source_code) {
  // Try field_name for declarations
  TSNode id_node = ts_node_child_by_field_name(node, "name", 4);
  if (!ts_node_is_null(id_node)) {
    return get_node_text(id_node, source_code);
  }

  // Try direct identifier
  bool found = false;
  id_node = find_child_by_type(node, "Identifier", &found);
  if (found) {
    return get_node_text(id_node, source_code);
  }

  // For function declarations, check deeper
  if (is_node_type(node, "FunctionDeclaration")) {
    bool found = false;
    TSNode fn_proto = find_child_by_type(node, "FunctionProto", &found);
    if (found) {
      id_node = ts_node_child_by_field_name(fn_proto, "name", 4);
      if (!ts_node_is_null(id_node)) {
        return get_node_text(id_node, source_code);
      }
    }
  }

  if (is_node_type(node, "FnProto")) {
    TSNode fn_name = ts_node_child_by_field_name(node, "function", 8);
    if (!ts_node_is_null(fn_name)) {
      return get_node_text(fn_name, source_code);
    }

    bool found = false;
    TSNode id_from_children = find_child_by_type(node, "Identifier", &found);
    if (found) {
      return get_node_text(id_from_children, source_code);
    }
  }

  if (is_node_type(node, "VarDecl")) {
    TSNode var_name = ts_node_child_by_field_name(node, "variable_type_function", 22);
    if (!ts_node_is_null(var_name)) {
      return get_node_text(var_name, source_code);
    }
  }

  // Return empty string view if not found
  r2m_string_view_t empty = {0};
  return empty;
}

// Extract module name from file path
// Check if a node is in a comptime context
static bool is_in_comptime_context(TSNode node) {
  TSNode parent = ts_node_parent(node);
  while (!ts_node_is_null(parent)) {
    if (is_node_type(parent, "Comptime")) {
      return true;
    }
    parent = ts_node_parent(parent);
  }
  return false;
}

static bool node_has_pub_modifier(TSNode node) {
  uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(node, i);
    const char *child_type = ts_node_type(child);
    if (strcmp(child_type, "Pub") == 0 || strcmp(child_type, "KEYWORD_pub") == 0 ||
        strcmp(child_type, "pub") == 0) {
      return true;
    }
  }
  return false;
}

static bool has_pub_flag(TSNode node) {
  return node_has_pub_modifier(node);
}

static bool has_pub_prefix(const char *source_code, TSNode node) {
  if (!source_code) {
    return false;
  }

  uint32_t start_byte = ts_node_start_byte(node);
  size_t i = start_byte;

  while (i > 0 && (source_code[i - 1] == ' ' || source_code[i - 1] == '\t')) {
    i--;
  }

  if (i >= 3 && strncmp(&source_code[i - 3], "pub", 3) == 0) {
    if (i == 3 || source_code[i - 4] == '\n' || source_code[i - 4] == ' ' ||
        source_code[i - 4] == '\t' || source_code[i - 4] == '{') {
      return true;
    }
  }

  return false;
}

static bool is_top_level_var_decl(TSNode node) {
  TSNode current = node;
  while (!ts_node_is_null(current)) {
    TSNode parent = ts_node_parent(current);
    if (ts_node_is_null(parent)) {
      break;
    }

    const char *parent_type = ts_node_type(parent);
    if (strcmp(parent_type, "source_file") == 0) {
      return true;
    }

    if (strcmp(parent_type, "Block") == 0 || strcmp(parent_type, "TestDecl") == 0 ||
        strcmp(parent_type, "ContainerDecl") == 0 ||
        strcmp(parent_type, "ContainerField") == 0 ||
        strcmp(parent_type, "ComptimeDecl") == 0) {
      return false;
    }

    current = parent;
  }

  return false;
}

static bool is_function_scope_allowed(TSNode node) {
  TSNode current = node;
  while (!ts_node_is_null(current)) {
    TSNode parent = ts_node_parent(current);
    if (ts_node_is_null(parent)) {
      break;
    }

    const char *parent_type = ts_node_type(parent);
    if (strcmp(parent_type, "source_file") == 0) {
      return true;
    }

    if (strcmp(parent_type, "Decl") == 0 || strcmp(parent_type, "ContainerDecl") == 0 ||
        strcmp(parent_type, "ContainerField") == 0 || strcmp(parent_type, "VarDecl") == 0) {
      current = parent;
      continue;
    }

    if (strcmp(parent_type, "Block") == 0 || strcmp(parent_type, "TestDecl") == 0 ||
        strcmp(parent_type, "ComptimeDecl") == 0) {
      return false;
    }

    current = parent;
  }

  return false;
}

static bool add_function_node(const r2m_parse_request_t *request,
                              const char *source_code,
                              TSNode node,
                              node_buffer_t *nodes) {
  if (!is_function_scope_allowed(node) || is_in_comptime_context(node)) {
    return true;
  }

  r2m_string_view_t func_name = extract_identifier(node, source_code);
  if (!func_name.data || func_name.len == 0) {
    return true;
  }

  if (!ensure_node_capacity(nodes, nodes->count + 1)) {
    return false;
  }

  r2m_node_t *func_node = &nodes->items[nodes->count];
  memset(func_node, 0, sizeof(r2m_node_t));

  r2m_string_view_t container_names[8] = {0};
  size_t container_count =
      collect_container_names(node, source_code, container_names, 8);

  char container_prefix[512];
  size_t prefix_len = 0;
  if (container_count > 0) {
    prefix_len = write_container_prefix(container_names, container_count,
                                        container_prefix,
                                        sizeof(container_prefix));
    if (prefix_len == 0) {
      return false;
    }
  }

  char func_id[1024];
  if (prefix_len > 0) {
    snprintf(func_id, sizeof(func_id), "func_%.*s_%s_%.*s",
             (int)request->file_path.len, request->file_path.data,
             container_prefix, (int)func_name.len, func_name.data);
  } else {
    snprintf(func_id, sizeof(func_id), "func_%.*s_%.*s",
             (int)request->file_path.len, request->file_path.data,
             (int)func_name.len, func_name.data);
  }

  size_t func_id_len = strlen(func_id);
  if (func_id_len > 0) {
    func_node->id.data = request->arena->alloc(request->arena->state, alignof(char),
                                               func_id_len + 1);
    if (!func_node->id.data) {
      return false;
    }
    strcpy((char *)func_node->id.data, func_id);
    func_node->id.len = func_id_len;
  }

  func_node->lang = r2m_string_view_from_cstr("zig");
  func_node->kind = R2M_NODE_FUNC;
  func_node->name = func_name;
  if (!set_function_fqname(func_node, request, container_names,
                           container_count, func_name)) {
    return false;
  }
  func_node->file.data = request->file_path.data;
  func_node->file.len = request->file_path.len;
  func_node->range.start = ts_point_to_position(ts_node_start_point(node));
  func_node->range.end = ts_point_to_position(ts_node_end_point(node));

  func_node->range.start.column = 1;
  func_node->range.end.column = 1;
  func_node->visibility = (has_pub_flag(node) || has_pub_prefix(source_code, node))
      ? R2M_VIS_PUBLIC
      : R2M_VIS_PRIVATE;
  func_node->origin_plugin = r2m_string_view_from_cstr("zig");

  nodes->count++;
  return true;
}

static bool add_type_node(const r2m_parse_request_t *request,
                          const char *source_code,
                          TSNode var_decl,
                          TSNode container,
                          node_buffer_t *nodes) {
  if (!is_top_level_var_decl(var_decl) || !is_struct_container(container)) {
    return true;
  }

  r2m_string_view_t type_name = extract_identifier(var_decl, source_code);
  if (!type_name.data || type_name.len == 0) {
    return true;
  }

  if (!ensure_node_capacity(nodes, nodes->count + 1)) {
    return false;
  }

  r2m_node_t *type_node = &nodes->items[nodes->count];
  memset(type_node, 0, sizeof(r2m_node_t));

  char type_id[1024];
  snprintf(type_id, sizeof(type_id), "type_%.*s_%.*s", (int)request->file_path.len,
           request->file_path.data, (int)type_name.len, type_name.data);

  size_t type_id_len = strlen(type_id);
  if (type_id_len > 0) {
    type_node->id.data = request->arena->alloc(request->arena->state, alignof(char),
                                               type_id_len + 1);
    if (!type_node->id.data) {
      return false;
    }
    strcpy((char *)type_node->id.data, type_id);
    type_node->id.len = type_id_len;
  }

  type_node->lang = r2m_string_view_from_cstr("zig");
  type_node->kind = R2M_NODE_TYPE;
  type_node->name = type_name;
  type_node->fqname = type_name;
  type_node->file.data = request->file_path.data;
  type_node->file.len = request->file_path.len;
  type_node->range.start = ts_point_to_position(ts_node_start_point(container));
  type_node->range.end = ts_point_to_position(ts_node_end_point(container));
  type_node->range.start.column = 1;
  type_node->visibility = (has_pub_flag(var_decl) || has_pub_prefix(source_code, var_decl))
      ? R2M_VIS_PUBLIC
      : R2M_VIS_PRIVATE;
  type_node->origin_plugin = r2m_string_view_from_cstr("zig");

  nodes->count++;
  return true;
}

static bool collect_declarations(const r2m_parse_request_t *request,
                                 const char *source_code,
                                 TSNode node,
                                 node_buffer_t *nodes) {
  const char *node_type = ts_node_type(node);

  if (strcmp(node_type, "FnProto") == 0) {
    if (!add_function_node(request, source_code, node, nodes)) {
      return false;
    }
  } else if (strcmp(node_type, "VarDecl") == 0) {
    TSNode container = find_descendant_by_type(node, "ContainerDecl", 6);
    if (ts_node_is_null(container)) {
      container = find_descendant_by_type(node, "ContainerDeclType", 6);
    }
    TSNode pending_container = container;

    uint32_t child_count = ts_node_child_count(node);
    for (uint32_t i = 0; i < child_count; i++) {
      TSNode child = ts_node_child(node, i);
      if (!collect_declarations(request, source_code, child, nodes)) {
        return false;
      }
    }

    if (!ts_node_is_null(pending_container)) {
      if (!add_type_node(request, source_code, node, pending_container, nodes)) {
        return false;
      }
    }
    return true;
  }

  uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(node, i);
    if (!collect_declarations(request, source_code, child, nodes)) {
      return false;
    }
  }

  return true;
}

// Parse a file and return Zig symbols using Tree-sitter
static r2m_status_t parse_file(const r2m_parse_request_t *request,
                               r2m_parse_response_t *response) {
  if (!request || !response || !request->arena || !request->content.data) {
    return R2M_STATUS_FATAL;
  }

  // Initialize response structure
  memset(response, 0, sizeof(r2m_parse_response_t));
  response->abi_version = R2M_FRONTEND_API_VERSION;
  response->struct_size = sizeof(r2m_parse_response_t);

  // Create file node
  r2m_node_t *file_node = (r2m_node_t *)request->arena->alloc(
      request->arena->state, alignof(r2m_node_t), sizeof(r2m_node_t));
  if (!file_node) {
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to allocate file node";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }


  memset(file_node, 0, sizeof(r2m_node_t));

  // Create file ID
  char file_id[512];
  snprintf(file_id, sizeof(file_id), "file_%.*s", (int)request->file_path.len,
           request->file_path.data);

  size_t file_id_len = strlen(file_id);
  if (file_id_len > 0) {
    file_node->id.data = request->arena->alloc(request->arena->state,
                                               alignof(char), file_id_len + 1);
    if (file_node->id.data) {
      strcpy((char *)file_node->id.data, file_id);
      file_node->id.len = file_id_len;
    }
  }

  file_node->lang = r2m_string_view_from_cstr("zig");
  file_node->kind = R2M_NODE_FILE;
  file_node->name.data = request->file_path.data;
  file_node->name.len = request->file_path.len;
  file_node->fqname.data = request->file_path.data;
  file_node->fqname.len = request->file_path.len;
  file_node->file.data = request->file_path.data;
  file_node->file.len = request->file_path.len;
  file_node->range.start.line = 1;
  file_node->range.start.column = 1;
  file_node->range.end.line = 1;
  file_node->range.end.column = 1;
  file_node->visibility = R2M_VIS_PUBLIC;
  file_node->origin_plugin = r2m_string_view_from_cstr("zig");

  // Initialize thread-local tree-sitter context
  r2m_status_t init_result = init_thread_local_context();
  if (init_result != R2M_STATUS_OK) {
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message =
        "Failed to initialize thread-local tree-sitter context";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  // Create null-terminated source code string for Tree-sitter
  if (request->content.len == 0) {
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Empty source code";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  char *source_code = (char *)request->arena->alloc(
      request->arena->state, alignof(char), request->content.len + 1);
  if (!source_code) {
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to allocate source code buffer";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  memcpy(source_code, request->content.data, request->content.len);
  source_code[request->content.len] = '\0';

  // Parse the source code with Tree-sitter
  TSTree *tree = ts_parser_parse_string(tl_context.parser, NULL, source_code,
                                        request->content.len);
  if (!tree) {
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to parse source code with Tree-sitter";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  TSNode root_node = ts_tree_root_node(tree);

  node_buffer_t nodes = {0};
  edge_buffer_t edges = {0};

  nodes.capacity = 16;
  nodes.items = malloc(nodes.capacity * sizeof(r2m_node_t));
  if (!nodes.items) {
    ts_tree_delete(tree);
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to allocate node buffer";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  edges.capacity = 16;
  edges.items = malloc(edges.capacity * sizeof(r2m_edge_t));
  if (!edges.items) {
    ts_tree_delete(tree);
    free_node_buffer(&nodes);
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to allocate edge buffer";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  if (!ensure_node_capacity(&nodes, 1)) {
    ts_tree_delete(tree);
    free_node_buffer(&nodes);
    free_edge_buffer(&edges);
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to grow node buffer";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  nodes.items[0] = *file_node;
  nodes.count = 1;

  if (!collect_declarations(request, source_code, root_node, &nodes)) {
    ts_tree_delete(tree);
    free_node_buffer(&nodes);
    free_edge_buffer(&edges);
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to collect Zig declarations";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  import_context_t import_ctx = {
      .request = request,
      .file_node = file_node,
      .source_code = source_code,
      .edges = &edges,
  };

  if (!collect_import_edges_recursive(&import_ctx, root_node)) {
    ts_tree_delete(tree);
    free_node_buffer(&nodes);
    free_edge_buffer(&edges);
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to collect Zig imports";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  ts_tree_delete(tree);

  r2m_node_t *final_nodes = request->arena->alloc(
      request->arena->state, alignof(r2m_node_t), nodes.count * sizeof(r2m_node_t));
  r2m_edge_t *final_edges = NULL;
  if (edges.count > 0) {
    final_edges = request->arena->alloc(request->arena->state, alignof(r2m_edge_t),
                                        edges.count * sizeof(r2m_edge_t));
  }

  if (!final_nodes || (edges.count > 0 && !final_edges)) {
    free_node_buffer(&nodes);
    free_edge_buffer(&edges);
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to allocate final arrays";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  memcpy(final_nodes, nodes.items, nodes.count * sizeof(r2m_node_t));
  if (edges.count > 0) {
    memcpy(final_edges, edges.items, edges.count * sizeof(r2m_edge_t));
  }

  size_t final_node_count = nodes.count;
  size_t final_edge_count = edges.count;

  free_node_buffer(&nodes);
  free_edge_buffer(&edges);

  response->nodes = final_nodes;
  response->node_count = final_node_count;
  response->edges = final_edges;
  response->edge_count = final_edge_count;
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

  summary->id = r2m_string_view_from_cstr("zig");
  summary->version = r2m_string_view_from_cstr("0.2.0");
  summary->schema_min = R2M_SCHEMA_VERSION;
  summary->schema_max = R2M_SCHEMA_VERSION;

  return R2M_STATUS_OK;
}

// Plugin teardown
static r2m_status_t teardown(void) {
  cleanup_thread_local_context();
  return R2M_STATUS_OK;
}

// Legacy shutdown for compatibility
static bool shutdown(void) {
  teardown();
  return true;
}

// Plugin interface definition
static const r2m_frontend_v1_t zig_frontend = {
    .abi_version = R2M_FRONTEND_API_VERSION,
    .struct_size = sizeof(r2m_frontend_v1_t),
    .id = "zig",
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
  return &zig_frontend;
}
