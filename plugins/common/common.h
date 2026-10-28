#ifndef R2M_PLUGINS_COMMON_H
#define R2M_PLUGINS_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

static inline bool r2m_ends_with_n(
    const char *s,
    size_t len_s,
    const char *suffix
)
{
    if (!s || !suffix) {
        return false;
    }

    const size_t len_suffix = strlen(suffix);
    if (len_suffix == 0) {
        return true;
    }
    if (len_suffix > len_s) {
        return false;
    }

    return memcmp(s + (len_s - len_suffix), suffix, len_suffix) == 0;
}

static inline bool r2m_has_any_suffix_n(
    const char *s,
    size_t len_s,
    const char *const *suffixes,
    size_t count
)
{
    if (!s || !suffixes) {
        return false;
    }

    for (size_t i = 0; i < count; i++) {
        if (suffixes[i] && r2m_ends_with_n(s, len_s, suffixes[i])) {
            return true;
        }
    }

    return false;
}

static inline bool r2m_ends_with(const char *s, const char *suffix) {
    return s && suffix ? r2m_ends_with_n(s, strlen(s), suffix) : false;
}

static inline bool r2m_has_any_suffix(
    const char *s,
    const char *const *suffixes,
    size_t count
)
{
    return s && suffixes
        ? r2m_has_any_suffix_n(s, strlen(s), suffixes, count)
        : false;
}

#endif // R2M_PLUGINS_COMMON_H
