#ifndef VOX_SHERPA_H_
#define VOX_SHERPA_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum VoxSherpaModelType {
  VOX_SHERPA_FUNASR_NANO = 0,
  VOX_SHERPA_WHISPER = 1,
  VOX_SHERPA_PARAFORMER = 2,
} VoxSherpaModelType;

typedef struct VoxSherpaModelConfig {
  VoxSherpaModelType type;
  const char *model;
  const char *encoder;
  const char *decoder;
  const char *tokens;
  const char *embedding;
  const char *tokenizer;
  const char *language;
  int32_t num_threads;
} VoxSherpaModelConfig;

typedef struct VoxSherpaRecognizer VoxSherpaRecognizer;

VoxSherpaRecognizer *VoxSherpaCreateRecognizer(
    const VoxSherpaModelConfig *config);
void VoxSherpaDestroyRecognizer(VoxSherpaRecognizer *recognizer);
char *VoxSherpaTranscribe(VoxSherpaRecognizer *recognizer,
                          const float *samples, int32_t count,
                          int32_t sample_rate);
void VoxSherpaFreeText(char *text);

#ifdef __cplusplus
}
#endif

#endif
