#ifndef R2M_PLUGINS_COMMON_ABI_H
#define R2M_PLUGINS_COMMON_ABI_H

#include "../../include/frontend.h"

static inline r2m_status_t r2m_plugin_noop_init(
    const r2m_init_context_t *context
)
{
    return context ? R2M_STATUS_OK : R2M_STATUS_FATAL;
}

static inline r2m_status_t r2m_plugin_noop_teardown(void) {
    return R2M_STATUS_OK;
}

static inline bool r2m_plugin_noop_shutdown(void) {
    return true;
}

#endif // R2M_PLUGINS_COMMON_ABI_H
