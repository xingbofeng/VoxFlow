#ifndef VF_QWEN_BRIDGE_H
#define VF_QWEN_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(VF_QWEN_BRIDGE_EXPORTS)
#define VF_QWEN_API __declspec(dllexport)
#else
#define VF_QWEN_API __declspec(dllimport)
#endif
#define VF_QWEN_CALL __cdecl
#else
#define VF_QWEN_API
#define VF_QWEN_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define VF_QWEN_ABI_VERSION 1
#define VF_QWEN_BACKEND_PRODUCTION 0
#define VF_QWEN_BACKEND_TEST 1

typedef struct vf_qwen_runtime_s* vf_qwen_runtime;
typedef struct vf_qwen_session_s* vf_qwen_session;

typedef enum vf_qwen_status_e {
    VF_QWEN_OK = 0,
    VF_QWEN_ERROR_INVALID_ARGUMENT = -1,
    VF_QWEN_ERROR_INVALID_STATE = -2,
    VF_QWEN_ERROR_OUT_OF_MEMORY = -3,
    VF_QWEN_ERROR_RUNTIME = -4,
    VF_QWEN_ERROR_CANCELLED = -5
} vf_qwen_status;

typedef enum vf_qwen_poll_result_e {
    VF_QWEN_POLL_ERROR = -1,
    VF_QWEN_POLL_EMPTY = 0,
    VF_QWEN_POLL_EVENT = 1,
    VF_QWEN_POLL_COMPLETED = 2
} vf_qwen_poll_result;

typedef enum vf_qwen_event_kind_e {
    VF_QWEN_EVENT_READY = 1,
    VF_QWEN_EVENT_SPEECH_STARTED = 2,
    VF_QWEN_EVENT_PARTIAL = 3,
    VF_QWEN_EVENT_FINAL = 4,
    VF_QWEN_EVENT_PROGRESS = 5,
    VF_QWEN_EVENT_METRICS = 6,
    VF_QWEN_EVENT_ERROR = 7
} vf_qwen_event_kind;

/* The UTF-8 text pointer remains valid until the next poll for this session. */
typedef struct vf_qwen_event_s {
    vf_qwen_event_kind kind;
    int64_t revision;
    const char* text;
    size_t text_length;
    double value;
} vf_qwen_event;

VF_QWEN_API int VF_QWEN_CALL vf_qwen_abi_version(void);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_backend_kind(void);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_runtime_create(
    const char* model_path_utf8,
    vf_qwen_runtime* runtime_out);

VF_QWEN_API void VF_QWEN_CALL vf_qwen_runtime_destroy(vf_qwen_runtime runtime);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_session_create(
    vf_qwen_runtime runtime,
    int variant,
    vf_qwen_session* session_out);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_session_start(vf_qwen_session session);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_session_push_pcm16(
    vf_qwen_session session,
    const int16_t* samples,
    size_t sample_count);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_session_poll(
    vf_qwen_session session,
    vf_qwen_event* event_out);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_session_finish(vf_qwen_session session);

VF_QWEN_API void VF_QWEN_CALL vf_qwen_session_cancel(vf_qwen_session session);

VF_QWEN_API int VF_QWEN_CALL vf_qwen_session_last_error(
    vf_qwen_session session,
    char* destination,
    size_t destination_capacity,
    size_t* required_bytes_out);

VF_QWEN_API void VF_QWEN_CALL vf_qwen_session_destroy(vf_qwen_session session);

#ifdef __cplusplus
}
#endif

#endif
