#include "sherpa-onnx/c-api/c-api.h"
#include "vox-sherpa.h"

#include <stdlib.h>
#include <string.h>

struct VoxSherpaRecognizer {
  const SherpaOnnxOfflineRecognizer *recognizer;
};

VoxSherpaRecognizer *VoxSherpaCreateRecognizer(
    const VoxSherpaModelConfig *input) {
  if (input == NULL) {
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.num_threads =
      input->num_threads > 0 ? input->num_threads : 2;
  config.model_config.provider = "cpu";
  config.decoding_method = "greedy_search";
  config.max_active_paths = 4;

  switch (input->type) {
    case VOX_SHERPA_FUNASR_NANO:
      config.model_config.funasr_nano.encoder_adaptor = input->encoder;
      config.model_config.funasr_nano.llm = input->decoder;
      config.model_config.funasr_nano.embedding = input->embedding;
      config.model_config.funasr_nano.tokenizer = input->tokenizer;
      config.model_config.funasr_nano.system_prompt =
          "You are a helpful assistant.";
      config.model_config.funasr_nano.user_prompt = "语音转写：";
      config.model_config.funasr_nano.max_new_tokens = 512;
      config.model_config.funasr_nano.temperature = 0.000001f;
      config.model_config.funasr_nano.top_p = 0.8f;
      config.model_config.funasr_nano.seed = 42;
      config.model_config.funasr_nano.language = input->language;
      config.model_config.funasr_nano.itn = 1;
      break;
    case VOX_SHERPA_WHISPER:
      config.model_config.whisper.encoder = input->encoder;
      config.model_config.whisper.decoder = input->decoder;
      config.model_config.whisper.language = input->language;
      config.model_config.whisper.task = "transcribe";
      config.model_config.whisper.tail_paddings = -1;
      config.model_config.tokens = input->tokens;
      break;
    case VOX_SHERPA_PARAFORMER:
      config.model_config.paraformer.model = input->model;
      config.model_config.tokens = input->tokens;
      break;
  }

  const SherpaOnnxOfflineRecognizer *recognizer =
      SherpaOnnxCreateOfflineRecognizer(&config);
  if (recognizer == NULL) {
    return NULL;
  }

  VoxSherpaRecognizer *wrapper =
      (VoxSherpaRecognizer *)malloc(sizeof(VoxSherpaRecognizer));
  if (wrapper == NULL) {
    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    return NULL;
  }
  wrapper->recognizer = recognizer;
  return wrapper;
}

void VoxSherpaDestroyRecognizer(VoxSherpaRecognizer *recognizer) {
  if (recognizer == NULL) {
    return;
  }
  SherpaOnnxDestroyOfflineRecognizer(recognizer->recognizer);
  free(recognizer);
}

char *VoxSherpaTranscribe(VoxSherpaRecognizer *recognizer,
                          const float *samples, int32_t count,
                          int32_t sample_rate) {
  if (recognizer == NULL || samples == NULL || count <= 0) {
    return NULL;
  }
  const SherpaOnnxOfflineStream *stream =
      SherpaOnnxCreateOfflineStream(recognizer->recognizer);
  if (stream == NULL) {
    return NULL;
  }

  SherpaOnnxAcceptWaveformOffline(stream, sample_rate, samples, count);
  SherpaOnnxDecodeOfflineStream(recognizer->recognizer, stream);
  const SherpaOnnxOfflineRecognizerResult *result =
      SherpaOnnxGetOfflineStreamResult(stream);
  char *text = NULL;
  if (result != NULL && result->text != NULL) {
    text = strdup(result->text);
  }
  if (result != NULL) {
    SherpaOnnxDestroyOfflineRecognizerResult(result);
  }
  SherpaOnnxDestroyOfflineStream(stream);
  return text;
}

void VoxSherpaFreeText(char *text) {
  free(text);
}
