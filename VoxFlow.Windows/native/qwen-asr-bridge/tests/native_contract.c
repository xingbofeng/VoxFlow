#include "vf_qwen_bridge.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <windows.h>

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "contract failure at line %d: %s\n", __LINE__, #condition); \
            return 1; \
        } \
    } while (0)

int main(void) {
    vf_qwen_runtime runtime = NULL;
    vf_qwen_session session = NULL;
    vf_qwen_event event;
    int16_t samples[] = {0, 1, -2, 32767};

    CHECK(vf_qwen_abi_version() == VF_QWEN_ABI_VERSION);
    CHECK(vf_qwen_runtime_create(NULL, &runtime) == VF_QWEN_ERROR_INVALID_ARGUMENT);
    CHECK(vf_qwen_runtime_create("deterministic-test-model", &runtime) == VF_QWEN_OK);
    CHECK(runtime != NULL);
    CHECK(vf_qwen_session_create(runtime, 7, &session) == VF_QWEN_ERROR_INVALID_ARGUMENT);
    CHECK(vf_qwen_session_create(runtime, 0, &session) == VF_QWEN_OK);
    CHECK(session != NULL);
    CHECK(vf_qwen_session_push_pcm16(session, samples, 4) == VF_QWEN_ERROR_INVALID_STATE);
    CHECK(vf_qwen_session_start(session) == VF_QWEN_OK);
    CHECK(vf_qwen_session_start(session) == VF_QWEN_ERROR_INVALID_STATE);

    char error[256];
    size_t required = 0;
    CHECK(vf_qwen_session_last_error(session, error, sizeof(error), &required) == VF_QWEN_OK);
    CHECK(required > 1);
    CHECK(strstr(error, "started") != NULL);

    CHECK(vf_qwen_session_push_pcm16(session, samples, 4) == VF_QWEN_OK);
    CHECK(vf_qwen_session_finish(session) == VF_QWEN_OK);

    int saw_ready = 0;
    int saw_speech = 0;
    int saw_partial = 0;
    int saw_final = 0;
    int saw_metrics = 0;
    for (int attempt = 0; attempt < 1000; attempt++) {
        int poll = vf_qwen_session_poll(session, &event);
        if (poll == VF_QWEN_POLL_COMPLETED) {
            break;
        }
        if (poll == VF_QWEN_POLL_EMPTY) {
            Sleep(1);
            continue;
        }
        CHECK(poll == VF_QWEN_POLL_EVENT);
        if (event.kind == VF_QWEN_EVENT_READY) saw_ready++;
        if (event.kind == VF_QWEN_EVENT_SPEECH_STARTED) saw_speech++;
        if (event.kind == VF_QWEN_EVENT_PARTIAL) {
            saw_partial++;
            CHECK(event.revision > 0);
            CHECK(event.text != NULL && event.text_length > 0);
        }
        if (event.kind == VF_QWEN_EVENT_FINAL) {
            saw_final++;
            CHECK(event.text != NULL && event.text_length > 0);
        }
        if (event.kind == VF_QWEN_EVENT_METRICS) saw_metrics++;
    }

    CHECK(saw_ready == 1);
    CHECK(saw_speech == 1);
    CHECK(saw_partial == 1);
    CHECK(saw_final == 1);
    CHECK(saw_metrics == 1);

    vf_qwen_session_cancel(session);
    vf_qwen_session_destroy(session);
    vf_qwen_runtime_destroy(runtime);
    return 0;
}
