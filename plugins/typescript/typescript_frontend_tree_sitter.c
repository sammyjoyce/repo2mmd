#include <pthread.h>
#include <stdalign.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../include/frontend.h"
#include "../common/common.h"
#include "tree_sitter/api.h"

// Thread-safe tree-sitter management
// Each thread gets its own completely isolated parser instance
typedef struct {
  TSLanguage *ts_language;
  TSLanguage *tsx_language;
  TSParser *parser;
  bool initialized;
  bool using_tsx;
} thread_local_ts_context_t;

static _Thread_local thread_local_ts_context_t tl_context = {0};

// Global mutex for one-time initialization
static pthread_mutex_t ts_init_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool global_languages_initialized = false;

// External declarations for the tree-sitter language functions
extern TSLanguage *tree_sitter_typescript(void);
extern TSLanguage *tree_sitter_tsx(void);

// Helper function to initialize thread-local tree-sitter context
static r2m_status_t init_thread_local_context(bool is_tsx) {
  // Initialize language singletons when needed.
  if (!tl_context.ts_language) {
    tl_context.ts_language = tree_sitter_typescript();
    if (!tl_context.ts_language) {
      return R2M_STATUS_FATAL;
    }
  }

  if (!tl_context.tsx_language) {
    tl_context.tsx_language = tree_sitter_tsx();
    if (!tl_context.tsx_language) {
      return R2M_STATUS_FATAL;
    }
  }

  // Lazily allocate the parser for this thread.
  if (!tl_context.parser) {
    tl_context.parser = ts_parser_new();
    if (!tl_context.parser) {
      return R2M_STATUS_FATAL;
    }
    tl_context.initialized = true;
  }

  const TSLanguage *target_language =
      is_tsx ? tl_context.tsx_language : tl_context.ts_language;

  if (tl_context.using_tsx != is_tsx) {
    if (!ts_parser_set_language(tl_context.parser, target_language)) {
      return R2M_STATUS_FATAL;
    }
    tl_context.using_tsx = is_tsx;
  }

  return R2M_STATUS_OK;
}

// Helper function to cleanup thread-local context
static void cleanup_thread_local_context(void) {
  if (tl_context.parser) {
    ts_parser_delete(tl_context.parser);
    tl_context.parser = NULL;
  }
  // Note: We don't delete language objects as they're singletons
  tl_context.initialized = false;
  tl_context.using_tsx = false;
}

// TSConfig path mapping structure
typedef struct {
  char *pattern;
  char *replacement;
} ts_path_mapping_t;

// TSConfig configuration
typedef struct {
  char *base_url;
  ts_path_mapping_t *path_mappings;
  size_t path_mapping_count;
  bool loaded;
} ts_config_t;

// Global TSConfig
static ts_config_t g_ts_config = {0};

// Simple JSON parsing for tsconfig.json (very basic implementation)
static char *extract_json_string_value(const char *json, const char *key) {
  if (!json || !key)
    return NULL;

  char search_key[256];
  snprintf(search_key, sizeof(search_key), "\"%s\"", key);

  char *key_pos = strstr(json, search_key);
  if (!key_pos)
    return NULL;

  // Find the colon after the key
  char *colon_pos = strchr(key_pos, ':');
  if (!colon_pos)
    return NULL;

  // Skip whitespace after colon
  char *value_start = colon_pos + 1;
  while (*value_start && (*value_start == ' ' || *value_start == '\t' ||
                          *value_start == '\n')) {
    value_start++;
  }

  if (*value_start != '"')
    return NULL;
  value_start++;  // Skip opening quote

  // Find the closing quote
  char *value_end = strchr(value_start, '"');
  if (!value_end)
    return NULL;

  size_t value_len = value_end - value_start;
  char *result = malloc(value_len + 1);
  if (result) {
    memcpy(result, value_start, value_len);
    result[value_len] = '\0';
  }

  return result;
}

// Load and parse tsconfig.json
static void load_tsconfig(const r2m_path_view_t *project_root) {
  if (g_ts_config.loaded)
    return;

  // Try to read tsconfig.json from project root
  char config_path[1024];
  snprintf(config_path, sizeof(config_path), "%.*s/tsconfig.json",
           (int)project_root->len, project_root->data);

  FILE *config_file = fopen(config_path, "r");
  if (!config_file) {
    g_ts_config.loaded = true;  // Mark as attempted even if not found
    return;
  }

  // Read file content
  fseek(config_file, 0, SEEK_END);
  long file_size = ftell(config_file);
  fseek(config_file, 0, SEEK_SET);

  char *config_content = malloc(file_size + 1);
  if (config_content) {
    fread(config_content, 1, file_size, config_file);
    config_content[file_size] = '\0';

    // Extract baseUrl
    char *base_url = extract_json_string_value(config_content, "baseUrl");
    if (base_url) {
      g_ts_config.base_url = base_url;
    }

    // For now, we'll use hardcoded common path mappings
    // In a full implementation, we'd parse the paths object properly
    g_ts_config.path_mapping_count = 5;
    g_ts_config.path_mappings =
        malloc(g_ts_config.path_mapping_count * sizeof(ts_path_mapping_t));

    if (g_ts_config.path_mappings) {
      g_ts_config.path_mappings[0].pattern = strdup("@/*");
      g_ts_config.path_mappings[0].replacement = strdup("");

      g_ts_config.path_mappings[1].pattern = strdup("@auth/*");
      g_ts_config.path_mappings[1].replacement = strdup("auth/");

      g_ts_config.path_mappings[2].pattern = strdup("@db/*");
      g_ts_config.path_mappings[2].replacement = strdup("database/");

      g_ts_config.path_mappings[3].pattern = strdup("@components/*");
      g_ts_config.path_mappings[3].replacement = strdup("components/");

      g_ts_config.path_mappings[4].pattern = strdup("@utils/*");
      g_ts_config.path_mappings[4].replacement = strdup("utils/");
    }

    free(config_content);
  }

  fclose(config_file);
  g_ts_config.loaded = true;
}

// Resolve module path using tsconfig mappings
static char *resolve_module_path(const char *module_name) {
  if (!module_name)
    return NULL;

  // Check if it matches any path mapping
  for (size_t i = 0; i < g_ts_config.path_mapping_count; i++) {
    const char *pattern = g_ts_config.path_mappings[i].pattern;
    const char *replacement = g_ts_config.path_mappings[i].replacement;

    // Simple pattern matching for patterns ending with /*
    size_t pattern_len = strlen(pattern);
    if (pattern_len >= 2 && strcmp(pattern + pattern_len - 2, "/*") == 0) {
      size_t prefix_len = pattern_len - 2;  // Remove /* from pattern
      if (strncmp(module_name, pattern, prefix_len) == 0) {
        const char *suffix = module_name + prefix_len;

        char *resolved = malloc(strlen(replacement) + strlen(suffix) + 1);
        if (resolved) {
          strcpy(resolved, replacement);
          strcat(resolved, suffix);
          return resolved;
        }
      }
    } else if (strcmp(module_name, pattern) == 0) {
      return strdup(replacement);
    }
  }

  // No mapping found, return original
  return strdup(module_name);
}

// Cleanup tsconfig resources
static void cleanup_tsconfig(void) {
  if (g_ts_config.base_url) {
    free(g_ts_config.base_url);
    g_ts_config.base_url = NULL;
  }

  if (g_ts_config.path_mappings) {
    for (size_t i = 0; i < g_ts_config.path_mapping_count; i++) {
      free(g_ts_config.path_mappings[i].pattern);
      free(g_ts_config.path_mappings[i].replacement);
    }
    free(g_ts_config.path_mappings);
    g_ts_config.path_mappings = NULL;
  }

  g_ts_config.path_mapping_count = 0;
  g_ts_config.loaded = false;
}

// Helper function to create a node
static r2m_node_t *create_node(r2m_arena_t *arena, const char *id_prefix,
                               const char *name, size_t name_len,
                               r2m_node_kind_t kind,
                               const r2m_path_view_t *file_path, uint32_t line,
                               uint32_t column) {
  r2m_node_t *node = (r2m_node_t *)arena->alloc(
      arena->state, alignof(r2m_node_t), sizeof(r2m_node_t));
  if (!node)
    return NULL;

  memset(node, 0, sizeof(r2m_node_t));

  // Create ID
  char id[512];
  snprintf(id, sizeof(id), "%s_%.*s_%u_%u", id_prefix, (int)name_len, name,
           line, column);

  node->id.data = arena->alloc(arena->state, alignof(char), strlen(id) + 1);
  if (node->id.data) {
    strcpy((char *)node->id.data, id);
    node->id.len = strlen(id);
  }

  node->lang = r2m_string_view_from_cstr("typescript");
  node->kind = kind;

  // Copy name to arena
  char *name_copy = arena->alloc(arena->state, alignof(char), name_len + 1);
  if (name_copy) {
    memcpy(name_copy, name, name_len);
    name_copy[name_len] = '\0';
    node->name.data = name_copy;
    node->name.len = name_len;
  } else {
    node->name.data = "";
    node->name.len = 0;
  }

  // Copy fqname to arena
  char *fqname_copy = arena->alloc(arena->state, alignof(char), name_len + 1);
  if (fqname_copy) {
    memcpy(fqname_copy, name, name_len);
    fqname_copy[name_len] = '\0';
    node->fqname.data = fqname_copy;
    node->fqname.len = name_len;
  } else {
    node->fqname.data = "";
    node->fqname.len = 0;
  }

  // Copy file path to arena
  char *file_copy =
      arena->alloc(arena->state, alignof(char), file_path->len + 1);
  if (file_copy) {
    memcpy(file_copy, file_path->data, file_path->len);
    file_copy[file_path->len] = '\0';
    node->file.data = file_copy;
    node->file.len = file_path->len;
  } else {
    node->file.data = "";
    node->file.len = 0;
  }
  node->range.start.line = line;
  node->range.start.column = column;
  node->range.end.line = line;
  node->range.end.column = column + (uint32_t)name_len;
  node->visibility = R2M_VIS_PUBLIC;
  node->origin_plugin = r2m_string_view_from_cstr("typescript");

  return node;
}

// Helper function to create a module node
static r2m_node_t *create_module_node(r2m_arena_t *arena,
                                      const char *module_name) {
  r2m_node_t *node = (r2m_node_t *)arena->alloc(
      arena->state, alignof(r2m_node_t), sizeof(r2m_node_t));
  if (!node)
    return NULL;

  memset(node, 0, sizeof(r2m_node_t));

  // Create ID
  char id[512];
  snprintf(id, sizeof(id), "ts_module_%s", module_name);

  node->id.data = arena->alloc(arena->state, alignof(char), strlen(id) + 1);
  if (node->id.data) {
    strcpy((char *)node->id.data, id);
    node->id.len = strlen(id);
  }

  node->lang = r2m_string_view_from_cstr("typescript");
  node->kind = R2M_NODE_MODULE;

  // Copy name to arena
  size_t name_len = strlen(module_name);
  char *name_copy = arena->alloc(arena->state, alignof(char), name_len + 1);
  if (name_copy) {
    memcpy(name_copy, module_name, name_len);
    name_copy[name_len] = '\0';
    node->name.data = name_copy;
    node->name.len = name_len;
  } else {
    node->name.data = "";
    node->name.len = 0;
  }

  // Copy fqname to arena
  char *fqname_copy = arena->alloc(arena->state, alignof(char), name_len + 1);
  if (fqname_copy) {
    memcpy(fqname_copy, module_name, name_len);
    fqname_copy[name_len] = '\0';
    node->fqname.data = fqname_copy;
    node->fqname.len = name_len;
  } else {
    node->fqname.data = "";
    node->fqname.len = 0;
  }

  // Set file path (empty for module nodes)
  node->file.data = "";
  node->file.len = 0;

  // Set range (default position)
  node->range.start.line = 1;
  node->range.start.column = 1;
  node->range.end.line = 1;
  node->range.end.column = 1;

  node->visibility = R2M_VIS_PUBLIC;
  node->origin_plugin = r2m_string_view_from_cstr("typescript");

  return node;
}

// Helper function to create an edge
static r2m_edge_t *create_edge(r2m_arena_t *arena, const r2m_string_view_t *src,
                               const char *dst_id, r2m_edge_rel_t rel,
                               r2m_certainty_t certainty, const char *reason) {
  r2m_edge_t *edge = (r2m_edge_t *)arena->alloc(
      arena->state, alignof(r2m_edge_t), sizeof(r2m_edge_t));
  if (!edge)
    return NULL;

  memset(edge, 0, sizeof(r2m_edge_t));

  edge->src = *src;

  edge->dst.data =
      arena->alloc(arena->state, alignof(char), strlen(dst_id) + 1);
  if (edge->dst.data) {
    strcpy((char *)edge->dst.data, dst_id);
    edge->dst.len = strlen(dst_id);
  }

  edge->rel = rel;
  edge->certainty = certainty;
  edge->certainty_reason = r2m_string_view_from_cstr(reason);

  return edge;
}

// Get text content from a tree-sitter node
static char *get_node_text(TSNode node, const char *source_code) {
  uint32_t start_byte = ts_node_start_byte(node);
  uint32_t end_byte = ts_node_end_byte(node);
  size_t length = end_byte - start_byte;

  char *text = malloc(length + 1);
  if (text) {
    memcpy(text, source_code + start_byte, length);
    text[length] = '\0';
  }
  return text;
}

// Get node position information
static void get_node_position(TSNode node, uint32_t *line, uint32_t *column) {
  TSPoint start_point = ts_node_start_point(node);
  *line = start_point.row + 1;       // Convert to 1-based
  *column = start_point.column + 1;  // Convert to 1-based
}

// Walk the tree and extract nodes and edges
// Simple module tracking structure
typedef struct {
  char **modules;
  size_t count;
  size_t capacity;
} module_tracker_t;

// Check if module was already created
static bool module_created(module_tracker_t *tracker, const char *module_name) {
  for (size_t i = 0; i < tracker->count; i++) {
    if (strcmp(tracker->modules[i], module_name) == 0) {
      return true;
    }
  }
  return false;
}

// Add module to tracker
static bool add_module(module_tracker_t *tracker, const char *module_name,
                       r2m_arena_t *arena) {
  if (tracker->count >= tracker->capacity) {
    return false;  // Simple approach - just fail if capacity exceeded
  }

  size_t name_len = strlen(module_name);
  char *name_copy = arena->alloc(arena->state, alignof(char), name_len + 1);
  if (name_copy) {
    memcpy(name_copy, module_name, name_len);
    name_copy[name_len] = '\0';
    tracker->modules[tracker->count++] = name_copy;
    return true;
  }
  return false;
}

static void walk_tree(TSNode node, const char *source_code, r2m_arena_t *arena,
                      const r2m_path_view_t *file_path, r2m_node_t **nodes,
                      size_t *node_count, size_t max_nodes, r2m_edge_t **edges,
                      size_t *edge_count, size_t max_edges,
                      const r2m_string_view_t *file_node_id,
                      module_tracker_t *module_tracker,
                      const r2m_parse_request_t *request) {
  if (*node_count >= max_nodes || *edge_count >= max_edges) {
    return;
  }

  const char *node_type = ts_node_type(node);

  // Handle different node types
  if (strcmp(node_type, "export_statement") == 0) {
    // Process export statements
    uint32_t child_count = ts_node_child_count(node);
    for (uint32_t i = 0; i < child_count; i++) {
      TSNode child = ts_node_child(node, i);
      const char *child_type = ts_node_type(child);

      if (strcmp(child_type, "function_declaration") == 0 ||
          strcmp(child_type, "class_declaration") == 0 ||
          strcmp(child_type, "interface_declaration") == 0 ||
          strcmp(child_type, "type_alias_declaration") == 0 ||
          strcmp(child_type, "lexical_declaration") == 0 ||
          strcmp(child_type, "variable_statement") == 0) {
        // Extract identifier - handle both identifier and type_identifier
        TSNode identifier = ts_node_named_child(child, 0);

        // For interfaces and classes, the identifier might be the second named
        // child
        if (ts_node_is_null(identifier) &&
            (strcmp(child_type, "class_declaration") == 0 ||
             strcmp(child_type, "interface_declaration") == 0)) {
          identifier = ts_node_named_child(child, 1);
        }

        // For lexical declarations, look inside for variable declarators
        if (ts_node_is_null(identifier) &&
            (strcmp(child_type, "lexical_declaration") == 0 ||
             strcmp(child_type, "variable_statement") == 0)) {
          TSNode declarator = ts_node_named_child(child, 0);
          if (!ts_node_is_null(declarator)) {
            identifier = ts_node_named_child(declarator, 0);
          }
        }

        if (!ts_node_is_null(identifier)) {
          char *name = get_node_text(identifier, source_code);
          if (name) {
            uint32_t line, column;
            get_node_position(identifier, &line, &column);

            r2m_node_kind_t kind;
            const char *prefix;
            if (strcmp(child_type, "function_declaration") == 0) {
              kind = R2M_NODE_FUNC;
              prefix = "ts_func";
            } else if (strcmp(child_type, "class_declaration") == 0 ||
                       strcmp(child_type, "interface_declaration") == 0) {
              kind = R2M_NODE_TYPE;
              prefix = strcmp(child_type, "class_declaration") == 0
                           ? "ts_class"
                           : "ts_interface";
            } else if (strcmp(child_type, "type_alias_declaration") == 0) {
              kind = R2M_NODE_TYPE;
              prefix = "ts_type";
            } else {
              kind = R2M_NODE_VAR;
              prefix = "ts_var";
            }

            r2m_node_t *export_node =
                create_node(arena, prefix, name, strlen(name), kind, file_path,
                            line, column);
            if (export_node && *node_count < max_nodes) {
              (*nodes)[(*node_count)++] = *export_node;

              // Create containment edge from file to exported node
              r2m_edge_t *contain_edge = create_edge(
                  arena, file_node_id, (char *)export_node->id.data,
                  R2M_EDGE_CONTAINS, R2M_CERT_STATIC, "export_declaration");
              if (contain_edge && *edge_count < max_edges) {
                (*edges)[(*edge_count)++] = *contain_edge;
              }
            }
            free(name);
          }
        }
      }
    }
  } else if (strcmp(node_type, "import_statement") == 0) {
    // Process import statements
    uint32_t child_count = ts_node_child_count(node);
    for (uint32_t i = 0; i < child_count; i++) {
      TSNode child = ts_node_child(node, i);
      const char *child_type = ts_node_type(child);

      if (strcmp(child_type, "string") == 0) {
        char *module_name = get_node_text(child, source_code);
        if (module_name) {
          // Remove quotes
          if (module_name[0] == '"' || module_name[0] == '\'') {
            memmove(module_name, module_name + 1, strlen(module_name));
            module_name[strlen(module_name) - 1] = '\0';
          }

          // Apply tsconfig.json path resolution
          char *resolved_module = resolve_module_path(module_name);
          const char *final_module =
              resolved_module ? resolved_module : module_name;

          // Log that we're processing an import
          if (request->host && request->host->log) {
            char log_msg[256];
            snprintf(log_msg, sizeof(log_msg), "Processing import: %s -> %s",
                     module_name, final_module);
            request->host->log(request->host->log_state, R2M_SEV_INFO, log_msg);
          }

          // Create module node (always create for now to debug)
          r2m_node_t *module_node = create_module_node(arena, final_module);
          if (module_node && *node_count < max_nodes) {
            (*nodes)[(*node_count)++] = *module_node;
            if (!module_created(module_tracker, final_module)) {
              add_module(module_tracker, final_module, arena);
            }
            if (request->host && request->host->log) {
              char log_msg[256];
              snprintf(log_msg, sizeof(log_msg),
                       "Created module node: %s, node count: %zu", final_module,
                       *node_count);
              request->host->log(request->host->log_state, R2M_SEV_INFO,
                                 log_msg);
            }
          } else {
            // Debug: track failed creations
            if (request->host && request->host->log) {
              char log_msg[256];
              snprintf(log_msg, sizeof(log_msg),
                       "Failed to create module node: %s, node_count: %zu, "
                       "max_nodes: %zu",
                       final_module, *node_count, max_nodes);
              request->host->log(request->host->log_state, R2M_SEV_WARN,
                                 log_msg);
            }
          }

          // Create import edge
          char target_id[768];
          snprintf(target_id, sizeof(target_id), "ts_module_%s", final_module);

          r2m_edge_t *import_edge =
              create_edge(arena, file_node_id, target_id, R2M_EDGE_IMPORTS,
                          R2M_CERT_STATIC, "import_statement");
          if (import_edge && *edge_count < max_edges) {
            (*edges)[(*edge_count)++] = *import_edge;
          }
          free(module_name);
          if (resolved_module) {
            free(resolved_module);
          }
        }
      }
    }
  }

  // Extract dynamic imports
  if (strcmp(node_type, "import_expression") == 0) {
    uint32_t child_count = ts_node_child_count(node);
    if (child_count > 0) {
      TSNode source_node = ts_node_child(node, 0);
      char *module_name = get_node_text(source_node, source_code);
      if (module_name && strlen(module_name) > 0) {
        // Remove quotes if present
        if (module_name[0] == '"' || module_name[0] == '\'') {
          memmove(module_name, module_name + 1, strlen(module_name));
          module_name[strlen(module_name) - 1] = '\0';
        }

        char *resolved_module = resolve_module_path(module_name);
        const char *final_module =
            resolved_module ? resolved_module : module_name;

        // Create module node (always create for now to debug)
        r2m_node_t *module_node = create_module_node(arena, final_module);
        if (module_node && *node_count < max_nodes) {
          (*nodes)[(*node_count)++] = *module_node;
          if (!module_created(module_tracker, final_module)) {
            add_module(module_tracker, final_module, arena);
          }
        }

        char target_id[768];
        snprintf(target_id, sizeof(target_id), "ts_module_%s", final_module);

        r2m_edge_t *dynamic_import_edge =
            create_edge(arena, file_node_id, target_id, R2M_EDGE_IMPORTS,
                        R2M_CERT_DYNAMIC, "dynamic_import");
        if (dynamic_import_edge && *edge_count < max_edges) {
          (*edges)[(*edge_count)++] = *dynamic_import_edge;
        }
        free(module_name);
        if (resolved_module) {
          free(resolved_module);
        }
      }
    }
  }

  // Extract export ... from statements
  if (strcmp(node_type, "export_statement") == 0) {
    uint32_t child_count = ts_node_child_count(node);
    for (uint32_t i = 0; i < child_count; i++) {
      TSNode child = ts_node_child(node, i);
      const char *child_type = ts_node_type(child);

      if (strcmp(child_type, "export_clause") == 0) {
        // Look for the source in the export statement
        for (uint32_t j = i + 1; j < child_count; j++) {
          TSNode next_child = ts_node_child(node, j);
          const char *next_type = ts_node_type(next_child);
          if (strcmp(next_type, "string") == 0) {
            char *module_name = get_node_text(next_child, source_code);
            if (module_name) {
              // Remove quotes
              if (module_name[0] == '"' || module_name[0] == '\'') {
                memmove(module_name, module_name + 1, strlen(module_name));
                module_name[strlen(module_name) - 1] = '\0';
              }

              char *resolved_module = resolve_module_path(module_name);
              const char *final_module =
                  resolved_module ? resolved_module : module_name;

              char target_id[768];
              snprintf(target_id, sizeof(target_id), "ts_module_%s",
                       final_module);

              r2m_edge_t *reexport_edge =
                  create_edge(arena, file_node_id, target_id, R2M_EDGE_IMPORTS,
                              R2M_CERT_STATIC, "reexport");
              if (reexport_edge && *edge_count < max_edges) {
                (*edges)[(*edge_count)++] = *reexport_edge;
              }
              free(module_name);
              if (resolved_module) {
                free(resolved_module);
              }
            }
            break;
          }
        }
      }
    }
  }

  // Extract function calls
  if (strcmp(node_type, "call_expression") == 0) {
    uint32_t child_count = ts_node_child_count(node);
    if (child_count > 0) {
      TSNode function_node = ts_node_child(node, 0);
      const char *function_type = ts_node_type(function_node);

      // Handle different types of function references
      if (strcmp(function_type, "identifier") == 0 ||
          strcmp(function_type, "member_expression") == 0 ||
          strcmp(function_type, "property_access_expression") == 0) {
        char *function_name = get_node_text(function_node, source_code);
        if (function_name && strlen(function_name) > 0 &&
            strlen(function_name) < 128) {
          // Filter out language keywords and common non-function calls
          bool is_keyword = false;
          const char *keywords[] = {
              "if",       "for",      "while",  "switch",     "return",
              "break",    "continue", "throw",  "try",        "catch",
              "finally",  "new",      "typeof", "instanceof", "delete",
              "void",     "in",       "await",  "yield",      "class",
              "function", "var",      "let",    "const",      "import",
              "export"};

          for (size_t k = 0; k < sizeof(keywords) / sizeof(keywords[0]); k++) {
            if (strcmp(function_name, keywords[k]) == 0) {
              is_keyword = true;
              break;
            }
          }

          // Additional filtering for common property access that aren't
          // function calls
          if (!is_keyword && strncmp(function_name, "console.", 8) != 0 &&
              strncmp(function_name, "process.", 8) != 0 &&
              strncmp(function_name, "Math.", 5) != 0 &&
              strncmp(function_name, "Array.", 6) != 0 &&
              strncmp(function_name, "Object.", 7) != 0 &&
              strncmp(function_name, "String.", 7) != 0 &&
              strncmp(function_name, "Number.", 7) != 0) {
            // Create call edge
            char target_id[512];

            // For member expressions, extract the method name part
            char *method_name = function_name;
            char *dot_pos = strrchr(function_name, '.');
            if (dot_pos) {
              method_name = dot_pos + 1;
            }

            if (strlen(method_name) > 0) {
              snprintf(target_id, sizeof(target_id), "ts_func_%s", method_name);

              r2m_edge_t *call_edge =
                  create_edge(arena, file_node_id, target_id, R2M_EDGE_CALLS,
                              R2M_CERT_STATIC, "function_call");
              if (call_edge && *edge_count < max_edges) {
                (*edges)[(*edge_count)++] = *call_edge;
              }
            }
          }
          free(function_name);
        }
      }
    }
  }

  // Extract type references and constructor calls
  if (strcmp(node_type, "new_expression") == 0) {
    uint32_t child_count = ts_node_child_count(node);
    if (child_count > 1) {
      TSNode type_node = ts_node_child(node, 1);  // The type after 'new'
      char *type_name = get_node_text(type_node, source_code);
      if (type_name && strlen(type_name) > 0 && strlen(type_name) < 64) {
        // Create constructor call edge
        char target_id[512];
        snprintf(target_id, sizeof(target_id), "ts_type_%s", type_name);

        r2m_edge_t *constructor_edge =
            create_edge(arena, file_node_id, target_id, R2M_EDGE_CALLS,
                        R2M_CERT_STATIC, "constructor_call");
        if (constructor_edge && *edge_count < max_edges) {
          (*edges)[(*edge_count)++] = *constructor_edge;
        }

        // Also create type reference edge
        r2m_edge_t *type_ref_edge =
            create_edge(arena, file_node_id, target_id, R2M_EDGE_CALLS,
                        R2M_CERT_STATIC, "type_reference");
        if (type_ref_edge && *edge_count < max_edges) {
          (*edges)[(*edge_count)++] = *type_ref_edge;
        }
        free(type_name);
      }
    }
  }

  // Extract type annotations
  if (strcmp(node_type, "type_annotation") == 0) {
    uint32_t child_count = ts_node_child_count(node);
    if (child_count > 0) {
      TSNode type_node = ts_node_child(node, 0);
      char *type_name = get_node_text(type_node, source_code);
      if (type_name && strlen(type_name) > 0 && strlen(type_name) < 64) {
        // Create type reference edge
        char target_id[512];
        snprintf(target_id, sizeof(target_id), "ts_type_%s", type_name);

        r2m_edge_t *type_ref_edge =
            create_edge(arena, file_node_id, target_id, R2M_EDGE_CALLS,
                        R2M_CERT_STATIC, "type_annotation");
        if (type_ref_edge && *edge_count < max_edges) {
          (*edges)[(*edge_count)++] = *type_ref_edge;
        }
        free(type_name);
      }
    }
  }

  // Extract variable declarations with types
  if (strcmp(node_type, "variable_declaration") == 0) {
    uint32_t child_count = ts_node_child_count(node);
    for (uint32_t i = 0; i < child_count; i++) {
      TSNode child = ts_node_child(node, i);
      const char *child_type = ts_node_type(child);
      if (strcmp(child_type, "variable_declarator") == 0) {
        // Look for type annotation in the declarator
        uint32_t declarator_children = ts_node_child_count(child);
        for (uint32_t j = 0; j < declarator_children; j++) {
          TSNode declarator_child = ts_node_child(child, j);
          const char *declarator_type = ts_node_type(declarator_child);
          if (strcmp(declarator_type, "type_annotation") == 0) {
            TSNode type_annotation_child = ts_node_child(declarator_child, 0);
            char *type_name = get_node_text(type_annotation_child, source_code);
            if (type_name && strlen(type_name) > 0 && strlen(type_name) < 64) {
              // Create type reference edge
              char target_id[512];
              snprintf(target_id, sizeof(target_id), "ts_type_%s", type_name);

              r2m_edge_t *type_ref_edge =
                  create_edge(arena, file_node_id, target_id, R2M_EDGE_CALLS,
                              R2M_CERT_STATIC, "variable_type");
              if (type_ref_edge && *edge_count < max_edges) {
                (*edges)[(*edge_count)++] = *type_ref_edge;
              }
              free(type_name);
            }
          }
        }
      }
    }
  }

  // Extract JSX elements for TSX files
  if (strcmp(node_type, "jsx_element") == 0 ||
      strcmp(node_type, "jsx_self_closing_element") == 0) {
    uint32_t child_count = ts_node_child_count(node);
    if (child_count > 0) {
      TSNode opening_element = ts_node_child(node, 0);
      if (!ts_node_is_null(opening_element)) {
        TSNode element_name = ts_node_child(opening_element, 1);  // Skip '<'
        if (!ts_node_is_null(element_name)) {
          char *component_name = get_node_text(element_name, source_code);
          if (component_name && strlen(component_name) > 0 &&
              strlen(component_name) < 64) {
            // Check if it's a React component (starts with uppercase)
            if (component_name[0] >= 'A' && component_name[0] <= 'Z') {
              char target_id[512];
              snprintf(target_id, sizeof(target_id), "ts_component_%s",
                       component_name);

              r2m_edge_t *component_edge =
                  create_edge(arena, file_node_id, target_id, R2M_EDGE_CALLS,
                              R2M_CERT_STATIC, "jsx_component");
              if (component_edge && *edge_count < max_edges) {
                (*edges)[(*edge_count)++] = *component_edge;
              }
            }
            free(component_name);
          }
        }
      }
    }
  }

  // Extract JSX fragment
  if (strcmp(node_type, "jsx_fragment") == 0) {
    // JSX fragments don't have component names but we can track their usage
    r2m_edge_t *fragment_edge =
        create_edge(arena, file_node_id, "jsx_fragment", R2M_EDGE_CALLS,
                    R2M_CERT_STATIC, "jsx_fragment");
    if (fragment_edge && *edge_count < max_edges) {
      (*edges)[(*edge_count)++] = *fragment_edge;
    }
  }

  // Recursively walk children
  uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(node, i);
    walk_tree(child, source_code, arena, file_path, nodes, node_count,
              max_nodes, edges, edge_count, max_edges, file_node_id,
              module_tracker, request);
  }
}

// Check if plugin wants to handle a file
static bool wants_file(const r2m_path_view_t *path) {
  if (!path || !path->data)
    return false;

  static const char *const ts_suffixes[] = {".ts", ".tsx", ".js", ".jsx"};
  bool result =
      r2m_has_any_suffix_n(path->data, path->len, ts_suffixes,
                           sizeof(ts_suffixes) / sizeof(ts_suffixes[0]));
  return result;
}

// Determine if file is TSX based on extension
static bool is_tsx_file(const r2m_path_view_t *path) {
  static const char *const tsx_suffixes[] = {".tsx", ".jsx"};
  return path && path->data &&
         r2m_has_any_suffix_n(path->data, path->len, tsx_suffixes,
                              sizeof(tsx_suffixes) / sizeof(tsx_suffixes[0]));
}

// Plugin initialization
static r2m_status_t init(const r2m_init_context_t *context) {
  if (!context) {
    return R2M_STATUS_FATAL;
  }

  // Global initialization - just ensure tsconfig is loaded
  // Thread-local initialization happens in parse_file
  load_tsconfig(&context->plugin_path);

  return R2M_STATUS_OK;
}

// Parse a TypeScript file and extract nodes and edges
static r2m_status_t parse_file(const r2m_parse_request_t *request,
                               r2m_parse_response_t *response) {

  if (!request || !response || !request->arena) {
    return R2M_STATUS_FATAL;
  }

  // Initialize response structure
  memset(response, 0, sizeof(r2m_parse_response_t));
  response->abi_version = R2M_FRONTEND_API_VERSION;
  response->struct_size = sizeof(r2m_parse_response_t);

  // Create file node with basename as name
  const char *path_start = request->file_path.data;
  size_t path_len = request->file_path.len;

  // Find the last slash to get basename
  const char *basename = path_start;
  size_t basename_len = path_len;
  for (const char *p = path_start + path_len - 1; p >= path_start; p--) {
    if (*p == '/' || *p == '\\') {
      basename = p + 1;
      basename_len = path_len - (basename - path_start);
      break;
    }
  }

  r2m_node_t *file_node =
      create_node(request->arena, "ts_file", basename, basename_len,
                  R2M_NODE_FILE, &request->file_path, 1, 1);
  if (!file_node) {
    response->status = R2M_STATUS_RECOVERABLE_ERROR;
    response->error_message = "Failed to allocate file node";
    return R2M_STATUS_RECOVERABLE_ERROR;
  }

  // Allocate arrays for nodes and edges
  size_t max_nodes = 1000;
  size_t max_edges = 1000;

  r2m_node_t *nodes = (r2m_node_t *)request->arena->alloc(
      request->arena->state, alignof(r2m_node_t),
      max_nodes * sizeof(r2m_node_t));
  if (!nodes) {
    response->status = R2M_STATUS_FATAL;
    response->error_message = "Failed to allocate nodes array";
    return R2M_STATUS_FATAL;
  }
  memset(nodes, 0, max_nodes * sizeof(r2m_node_t));

  r2m_edge_t *edges = (r2m_edge_t *)request->arena->alloc(
      request->arena->state, alignof(r2m_edge_t),
      max_edges * sizeof(r2m_edge_t));
  if (!edges) {
    response->status = R2M_STATUS_FATAL;
    response->error_message = "Failed to allocate edges array";
    return R2M_STATUS_FATAL;
  }
  memset(edges, 0, max_edges * sizeof(r2m_edge_t));

  // Copy file_node as the first node
  nodes[0] = *file_node;
  size_t node_count = 1;
  size_t edge_count = 0;

  if (request->content.data && request->content.len > 0) {
    // Initialize thread-local tree-sitter context
    bool is_tsx = is_tsx_file(&request->file_path);
    r2m_status_t init_result = init_thread_local_context(is_tsx);
    if (init_result != R2M_STATUS_OK) {
      response->status = init_result;
      response->error_message =
          "Failed to initialize thread-local tree-sitter context";
      return init_result;
    }

    // Create null-terminated content for parsing
    char *content = request->arena->alloc(request->arena->state, alignof(char),
                                          request->content.len + 1);
    if (content) {
      memcpy(content, request->content.data, request->content.len);
      content[request->content.len] = '\0';

      // Parse with Tree-sitter using thread-local parser
      TSTree *tree = ts_parser_parse_string(tl_context.parser, NULL, content,
                                            request->content.len);
      if (tree) {
        TSNode root_node = ts_tree_root_node(tree);

        // Walk the tree and extract nodes and edges
        // Initialize module tracker
        module_tracker_t module_tracker = {0};
        char *module_buffer[50];  // Simple fixed-size buffer for modules
        module_tracker.modules = module_buffer;
        module_tracker.capacity = 50;

        walk_tree(root_node, content, request->arena, &request->file_path,
                  &nodes, &node_count, max_nodes, &edges, &edge_count,
                  max_edges, &file_node->id, &module_tracker, request);

        ts_tree_delete(tree);
      }
    }
  }

  response->nodes = nodes;
  response->node_count = node_count;
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

  summary->id = r2m_string_view_from_cstr("typescript");
  summary->version = r2m_string_view_from_cstr("0.3.0");
  summary->schema_min = R2M_SCHEMA_VERSION;
  summary->schema_max = R2M_SCHEMA_VERSION;

  return R2M_STATUS_OK;
}

// Plugin teardown
static r2m_status_t teardown(void) {
  // Cleanup thread-local context for current thread
  cleanup_thread_local_context();

  // Cleanup tsconfig resources
  cleanup_tsconfig();

  return R2M_STATUS_OK;
}

// Legacy shutdown for compatibility
static bool shutdown(void) {
  teardown();
  return true;
}

// Plugin interface definition
static const r2m_frontend_v1_t typescript_frontend = {
    .abi_version = R2M_FRONTEND_API_VERSION,
    .struct_size = sizeof(r2m_frontend_v1_t),
    .id = "typescript",
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
  return &typescript_frontend;
}
