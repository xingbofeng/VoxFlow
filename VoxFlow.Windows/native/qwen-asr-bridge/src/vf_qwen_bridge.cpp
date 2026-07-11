#include "vf_qwen_bridge.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <limits>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#if !defined(VF_QWEN_TEST_BACKEND)
extern "C" {
#include "qwen_asr.h"
}
#endif

struct vf_qwen_runtime_s {
    std::mutex inference_mutex;
#if !defined(VF_QWEN_TEST_BACKEND)
    qwen_ctx_t* context = nullptr;
#endif
};

struct owned_event {
    vf_qwen_event_kind kind = VF_QWEN_EVENT_PROGRESS;
    int64_t revision = 0;
    std::string text;
    double value = 0.0;
};

struct vf_qwen_session_s {
    vf_qwen_runtime runtime = nullptr;
    int variant = 0;
    std::mutex mutex;
    std::vector<int16_t> samples;
    std::deque<owned_event> events;
    owned_event last_polled;
    std::string last_error;
    std::string partial_text;
    std::thread worker;
    int64_t revision = 0;
    bool started = false;
    bool speech_started = false;
    bool finish_requested = false;
    bool cancelled = false;
    bool completed = false;
};

namespace {

constexpr size_t maximum_samples = static_cast<size_t>(16000) * 60 * 30;

void set_error(vf_qwen_session session, std::string message) {
    std::lock_guard<std::mutex> lock(session->mutex);
    session->last_error = std::move(message);
}

void enqueue(
    vf_qwen_session session,
    vf_qwen_event_kind kind,
    int64_t revision,
    std::string text,
    double value = 0.0) {
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->cancelled) {
        return;
    }

    session->events.push_back(owned_event{kind, revision, std::move(text), value});
}

void finish_with_error(vf_qwen_session session, std::string message) {
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (session->cancelled) {
            session->completed = true;
            return;
        }

        session->last_error = message;
        session->events.push_back(owned_event{
            VF_QWEN_EVENT_ERROR,
            session->revision,
            std::move(message),
            0.0});
        session->completed = true;
    }
}

#if !defined(VF_QWEN_TEST_BACKEND)
void token_callback(const char* piece, void* context) {
    if (piece == nullptr || context == nullptr) {
        return;
    }

    auto session = static_cast<vf_qwen_session>(context);
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->cancelled) {
        return;
    }

    session->partial_text.append(piece);
    session->events.push_back(owned_event{
        VF_QWEN_EVENT_PARTIAL,
        ++session->revision,
        session->partial_text,
        0.0});
}
#endif

void transcribe(vf_qwen_session session) {
    std::vector<int16_t> pcm;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        pcm = session->samples;
    }

    if (pcm.empty()) {
        finish_with_error(session, "No audio samples were provided to the Qwen session.");
        return;
    }

#if defined(VF_QWEN_TEST_BACKEND)
    const bool contains_speech = std::any_of(
        pcm.cbegin(),
        pcm.cend(),
        [](int16_t sample) { return sample != 0; });
    if (!contains_speech) {
        finish_with_error(session, "The deterministic Qwen test backend received silence.");
        return;
    }

    if (session->variant == 0) {
        enqueue(session, VF_QWEN_EVENT_PARTIAL, ++session->revision, "test preview");
    }
    enqueue(session, VF_QWEN_EVENT_FINAL, session->revision, "test transcript");
    enqueue(session, VF_QWEN_EVENT_METRICS, session->revision, std::string(), 1.0);
#else
    if (pcm.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
        finish_with_error(session, "The Qwen session audio exceeded the upstream sample limit.");
        return;
    }

    std::vector<float> samples(pcm.size());
    std::transform(
        pcm.cbegin(),
        pcm.cend(),
        samples.begin(),
        [](int16_t sample) { return static_cast<float>(sample) / 32768.0F; });

    char* text = nullptr;
    double elapsed_ms = 0.0;
    {
        std::lock_guard<std::mutex> inference_lock(session->runtime->inference_mutex);
        qwen_set_token_callback(session->runtime->context, token_callback, session);
        text = qwen_transcribe_stream(
            session->runtime->context,
            samples.data(),
            static_cast<int>(samples.size()));
        qwen_set_token_callback(session->runtime->context, nullptr, nullptr);
        elapsed_ms = session->runtime->context->perf_total_ms;
    }

    if (text == nullptr) {
        finish_with_error(session, "The upstream Qwen transcription failed.");
        return;
    }

    std::string final_text(text);
    std::free(text);
    if (final_text.empty()) {
        finish_with_error(session, "The upstream Qwen transcription returned an empty final.");
        return;
    }

    enqueue(session, VF_QWEN_EVENT_FINAL, session->revision, std::move(final_text));
    enqueue(session, VF_QWEN_EVENT_METRICS, session->revision, std::string(), elapsed_ms);
#endif

    std::lock_guard<std::mutex> lock(session->mutex);
    session->completed = true;
}

}  // namespace

extern "C" {

int VF_QWEN_CALL vf_qwen_abi_version(void) {
    return VF_QWEN_ABI_VERSION;
}

int VF_QWEN_CALL vf_qwen_runtime_create(
    const char* model_path_utf8,
    vf_qwen_runtime* runtime_out) {
    if (model_path_utf8 == nullptr || model_path_utf8[0] == '\0' || runtime_out == nullptr) {
        return VF_QWEN_ERROR_INVALID_ARGUMENT;
    }

    *runtime_out = nullptr;
    auto runtime = new (std::nothrow) vf_qwen_runtime_s();
    if (runtime == nullptr) {
        return VF_QWEN_ERROR_OUT_OF_MEMORY;
    }

#if !defined(VF_QWEN_TEST_BACKEND)
    runtime->context = qwen_load(model_path_utf8);
    if (runtime->context == nullptr) {
        delete runtime;
        return VF_QWEN_ERROR_RUNTIME;
    }
#endif

    *runtime_out = runtime;
    return VF_QWEN_OK;
}

void VF_QWEN_CALL vf_qwen_runtime_destroy(vf_qwen_runtime runtime) {
    if (runtime == nullptr) {
        return;
    }

#if !defined(VF_QWEN_TEST_BACKEND)
    qwen_free(runtime->context);
    runtime->context = nullptr;
#endif
    delete runtime;
}

int VF_QWEN_CALL vf_qwen_session_create(
    vf_qwen_runtime runtime,
    int variant,
    vf_qwen_session* session_out) {
    if (runtime == nullptr || session_out == nullptr || (variant != 0 && variant != 1)) {
        return VF_QWEN_ERROR_INVALID_ARGUMENT;
    }

    *session_out = nullptr;
    auto session = new (std::nothrow) vf_qwen_session_s();
    if (session == nullptr) {
        return VF_QWEN_ERROR_OUT_OF_MEMORY;
    }

    session->runtime = runtime;
    session->variant = variant;
    *session_out = session;
    return VF_QWEN_OK;
}

int VF_QWEN_CALL vf_qwen_session_start(vf_qwen_session session) {
    if (session == nullptr) {
        return VF_QWEN_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->started || session->finish_requested || session->cancelled) {
        session->last_error = "The Qwen session cannot be started in its current state.";
        return VF_QWEN_ERROR_INVALID_STATE;
    }

    session->started = true;
    session->events.push_back(owned_event{VF_QWEN_EVENT_READY, 0, std::string(), 0.0});
    return VF_QWEN_OK;
}

int VF_QWEN_CALL vf_qwen_session_push_pcm16(
    vf_qwen_session session,
    const int16_t* samples,
    size_t sample_count) {
    if (session == nullptr || (sample_count > 0 && samples == nullptr)) {
        return VF_QWEN_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(session->mutex);
    if (!session->started || session->finish_requested || session->cancelled) {
        session->last_error = "The Qwen session is not accepting audio in its current state.";
        return session->cancelled ? VF_QWEN_ERROR_CANCELLED : VF_QWEN_ERROR_INVALID_STATE;
    }

    if (sample_count > maximum_samples - session->samples.size()) {
        session->last_error = "The Qwen session exceeded its bounded audio capacity.";
        return VF_QWEN_ERROR_OUT_OF_MEMORY;
    }

    session->samples.insert(session->samples.end(), samples, samples + sample_count);
    if (!session->speech_started &&
        std::any_of(samples, samples + sample_count, [](int16_t sample) { return sample != 0; })) {
        session->speech_started = true;
        session->events.push_back(owned_event{
            VF_QWEN_EVENT_SPEECH_STARTED,
            0,
            std::string(),
            0.0});
    }
    return VF_QWEN_OK;
}

int VF_QWEN_CALL vf_qwen_session_poll(
    vf_qwen_session session,
    vf_qwen_event* event_out) {
    if (session == nullptr || event_out == nullptr) {
        return VF_QWEN_POLL_ERROR;
    }

    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->events.empty()) {
        return session->completed ? VF_QWEN_POLL_COMPLETED : VF_QWEN_POLL_EMPTY;
    }

    session->last_polled = std::move(session->events.front());
    session->events.pop_front();
    event_out->kind = session->last_polled.kind;
    event_out->revision = session->last_polled.revision;
    event_out->text = session->last_polled.text.data();
    event_out->text_length = session->last_polled.text.size();
    event_out->value = session->last_polled.value;
    return VF_QWEN_POLL_EVENT;
}

int VF_QWEN_CALL vf_qwen_session_finish(vf_qwen_session session) {
    if (session == nullptr) {
        return VF_QWEN_ERROR_INVALID_ARGUMENT;
    }

    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (!session->started || session->finish_requested || session->cancelled) {
            session->last_error = "The Qwen session cannot finish in its current state.";
            return session->cancelled ? VF_QWEN_ERROR_CANCELLED : VF_QWEN_ERROR_INVALID_STATE;
        }
        session->finish_requested = true;
    }

    try {
        session->worker = std::thread(transcribe, session);
    } catch (const std::exception&) {
        set_error(session, "The Qwen inference worker could not be started.");
        return VF_QWEN_ERROR_RUNTIME;
    }
    return VF_QWEN_OK;
}

void VF_QWEN_CALL vf_qwen_session_cancel(vf_qwen_session session) {
    if (session == nullptr) {
        return;
    }

    std::lock_guard<std::mutex> lock(session->mutex);
    session->cancelled = true;
    session->events.clear();
    session->completed = true;
}

int VF_QWEN_CALL vf_qwen_session_last_error(
    vf_qwen_session session,
    char* destination,
    size_t destination_capacity,
    size_t* required_bytes_out) {
    if (session == nullptr || required_bytes_out == nullptr) {
        return VF_QWEN_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(session->mutex);
    const size_t required = session->last_error.size() + 1;
    *required_bytes_out = required;
    if (destination == nullptr || destination_capacity < required) {
        return VF_QWEN_ERROR_INVALID_ARGUMENT;
    }

    std::memcpy(destination, session->last_error.c_str(), required);
    return VF_QWEN_OK;
}

void VF_QWEN_CALL vf_qwen_session_destroy(vf_qwen_session session) {
    if (session == nullptr) {
        return;
    }

    vf_qwen_session_cancel(session);
    if (session->worker.joinable()) {
        session->worker.join();
    }
    delete session;
}

}  // extern "C"
