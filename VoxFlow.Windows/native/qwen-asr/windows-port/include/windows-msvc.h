#ifndef VOXFLOW_QWEN_WINDOWS_MSVC_H
#define VOXFLOW_QWEN_WINDOWS_MSVC_H

#if !defined(_WIN32) || !defined(_MSC_VER)
#error "The qwen-asr Windows portability overlay requires MSVC on Windows."
#endif

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#ifndef _CRT_NONSTDC_NO_DEPRECATE
#define _CRT_NONSTDC_NO_DEPRECATE
#endif

/* The pinned upstream uses two GCC/POSIX spellings. Keep the compatibility
 * surface narrow instead of weakening MSVC warnings globally. */
#ifndef __attribute__
#define __attribute__(arguments)
#endif

#ifndef strdup
#define strdup _strdup
#endif

#endif /* VOXFLOW_QWEN_WINDOWS_MSVC_H */
