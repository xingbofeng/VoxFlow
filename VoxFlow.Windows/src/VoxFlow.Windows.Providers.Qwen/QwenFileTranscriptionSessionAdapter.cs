using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Qwen;

public sealed class QwenFileTranscriptionSessionAdapter
    : IFileTranscriptionProviderSessionAdapter
{
    private readonly DictationProviderFileTranscriptionAdapter adapter;

    public QwenFileTranscriptionSessionAdapter(
        Func<RecognitionLanguage, IDictationAsrProvider> providerFactory)
    {
        adapter = new DictationProviderFileTranscriptionAdapter(
            AsrProviderId.Qwen,
            providerFactory);
    }

    public AsrProviderId Provider => AsrProviderId.Qwen;

    public ValueTask<IDictationAsrSession> CreateSessionAsync(
        RecognitionLanguage language,
        Guid generation,
        CancellationToken cancellationToken) =>
        adapter.CreateSessionAsync(language, generation, cancellationToken);
}
