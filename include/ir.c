#include "ir.h"

const char *r2m_node_kind_to_string(r2m_node_kind_t kind) {
  switch (kind) {
  case R2M_NODE_MODULE:
    return "module";
  case R2M_NODE_FILE:
    return "file";
  case R2M_NODE_TYPE:
    return "type";
  case R2M_NODE_FUNC:
    return "func";
  case R2M_NODE_VAR:
    return "var";
  default:
    return "unknown";
  }
}

const char *r2m_edge_rel_to_string(r2m_edge_rel_t rel) {
  switch (rel) {
  case R2M_EDGE_IMPORTS:
    return "imports";
  case R2M_EDGE_INCLUDES:
    return "includes";
  case R2M_EDGE_CALLS:
    return "calls";
  case R2M_EDGE_CONTAINS:
    return "contains";
  case R2M_EDGE_EXTENDS:
    return "extends";
  case R2M_EDGE_IMPLEMENTS:
    return "implements";
  default:
    return "unknown";
  }
}

const char *r2m_certainty_to_string(r2m_certainty_t certainty) {
  switch (certainty) {
  case R2M_CERT_STATIC:
    return "static";
  case R2M_CERT_INDIRECT:
    return "indirect";
  case R2M_CERT_DYNAMIC:
    return "dynamic";
  case R2M_CERT_COMPTIME:
    return "comptime";
  case R2M_CERT_UNKNOWN:
    return "unknown";
  default:
    return "unknown";
  }
}

const char *r2m_visibility_to_string(r2m_visibility_t visibility) {
  switch (visibility) {
  case R2M_VIS_PUBLIC:
    return "public";
  case R2M_VIS_PRIVATE:
    return "private";
  case R2M_VIS_PACKAGE:
    return "package";
  default:
    return "unknown";
  }
}

const char *r2m_severity_to_string(r2m_severity_t severity) {
  switch (severity) {
  case R2M_SEV_INFO:
    return "info";
  case R2M_SEV_WARN:
    return "warn";
  case R2M_SEV_ERROR:
    return "error";
  default:
    return "unknown";
  }
}