#ifndef REPO2MMD_PLUGIN_CACHE_H
#define REPO2MMD_PLUGIN_CACHE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

// Cache format magic number ('R2MP')
#define R2M_PLUGIN_CACHE_MAGIC 0x52324D50

// Current cache format version
#define R2M_PLUGIN_CACHE_VERSION 1

// Maximum cache entry size (1GB)
#define R2M_CACHE_MAX_ENTRY_SIZE (1024 * 1024 * 1024)

// Cache entry flags
typedef enum {
  R2M_CACHE_FLAG_NONE = 0,
  R2M_CACHE_FLAG_HAS_DIAGNOSTICS = 1 << 0,
  R2M_CACHE_FLAG_HAS_EDGES = 1 << 1,
  R2M_CACHE_FLAG_INCREMENTAL = 1 << 2,
  R2M_CACHE_FLAG_PARTIAL_PARSE = 1 << 3,
  R2M_CACHE_FLAG_COMPRESSED = 1 << 4,
} r2m_cache_flags_t;

// Enhanced plugin cache header structure
typedef struct {
  // Magic and versioning
  uint32_t magic;           // Magic number for validation
  uint16_t version;         // Cache format version
  uint16_t header_size;     // Size of this header for forward compatibility
  uint32_t api_version;     // Frontend API version used
  uint32_t schema_version;  // IR schema version used

  // Plugin identification
  char plugin_id[64];        // Plugin ID string (null-terminated)
  char plugin_version[32];   // Plugin version string (null-terminated)
  uint64_t plugin_build_id;  // Plugin build identifier (optional)
  uint64_t plugin_id_hash;   // Hash of plugin ID string (for fast lookup)

  // File identification
  char file_path[512];  // File path (null-terminated)
  uint64_t file_hash;   // Hash of source file content
  uint64_t path_hash;   // Hash of file path
  uint64_t file_mtime;  // File modification time (unix timestamp)
  uint64_t file_size;   // File size in bytes

  // Timestamps
  uint64_t created_unix_ms;   // Creation timestamp (milliseconds)
  uint64_t last_accessed_ms;  // Last access timestamp (milliseconds)
  uint64_t ttl_ms;            // Time-to-live (0 = infinite)

  // Content metadata
  uint32_t flags;              // r2m_cache_flags_t bitmask
  uint32_t node_count;         // Number of nodes in cached data
  uint32_t edge_count;         // Number of edges in cached data
  uint32_t diagnostic_count;   // Number of diagnostics in cached data
  uint32_t data_size;          // Size of cached data following this header
  uint64_t uncompressed_size;  // Size before compression (0 if not compressed)

  // Performance metrics
  uint32_t parse_time_ns;         // Time taken to parse (nanoseconds)
  uint32_t memory_used_bytes;     // Peak memory usage during parse
  uint32_t plugin_parse_time_ns;  // Plugin-specific parse time

  // Checksums and integrity
  uint32_t header_checksum;   // CRC32 of header (excluding this field)
  uint32_t content_checksum;  // CRC32 of content
  uint64_t content_hash;      // xxHash64 of content for fast comparison

  // Reserved for future use
  uint8_t reserved[32];
} r2m_plugin_cache_header_t;

// Cache validation result
typedef enum {
  R2M_CACHE_VALID,             // Cache entry is valid and usable
  R2M_CACHE_INVALID_MAGIC,     // Invalid magic number
  R2M_CACHE_VERSION_MISMATCH,  // Unsupported cache version
  R2M_CACHE_API_MISMATCH,      // API version mismatch
  R2M_CACHE_SCHEMA_MISMATCH,   // Schema version mismatch
  R2M_CACHE_PLUGIN_MISMATCH,   // Plugin ID mismatch
  R2M_CACHE_FILE_MISMATCH,     // File content mismatch
  R2M_CACHE_CHECKSUM_ERROR,    // Checksum validation failed
  R2M_CACHE_CORRUPTED,         // Header or data corrupted
} r2m_cache_validation_result_t;

// Cache entry structure
typedef struct {
  r2m_plugin_cache_header_t header;
  void *data;  // Serialized IR data (nodes, edges, diagnostics)
} r2m_plugin_cache_entry_t;

// Function declarations for cache operations
uint64_t r2m_hash_plugin_id(const char *plugin_id);
uint64_t r2m_hash_file_content(const void *data, size_t size);
uint32_t r2m_calculate_cache_checksum(const r2m_plugin_cache_header_t *header,
                                      const void *data, size_t data_size);

r2m_cache_validation_result_t r2m_validate_cache_entry(
    const r2m_plugin_cache_entry_t *entry, uint32_t expected_api_version,
    uint32_t expected_schema_version, const char *expected_plugin_id,
    uint64_t expected_file_hash);

bool r2m_is_cache_entry_fresh(const r2m_plugin_cache_header_t *header,
                              uint64_t max_age_ms);

#ifdef __cplusplus
}
#endif

#endif  // REPO2MMD_PLUGIN_CACHE_H