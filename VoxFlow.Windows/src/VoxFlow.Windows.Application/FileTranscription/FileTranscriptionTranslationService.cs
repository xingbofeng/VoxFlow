using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public interface IFileTranscriptionTranslator
{
    ValueTask<string> TranslateAsync(
        string text,
        string targetLanguage,
        CancellationToken cancellationToken);
}

public sealed class FileTranscriptionTranslationUnavailableException()
    : Exception("The configured OpenAI translation provider is unavailable.");

public enum FileTranscriptionTranslationResult
{
    Succeeded,
    Failed,
    Cancelled,
    Unavailable,
    ResultUnavailable,
}

public sealed class FileTranscriptionTranslationService
{
    private readonly IFileTranscriptionJobRepository jobs;
    private readonly IFileTranscriptionTranslator translator;
    private readonly TimeProvider timeProvider;

    public FileTranscriptionTranslationService(
        IFileTranscriptionJobRepository jobs,
        IFileTranscriptionTranslator translator,
        TimeProvider timeProvider)
    {
        this.jobs = jobs ?? throw new ArgumentNullException(nameof(jobs));
        this.translator = translator ?? throw new ArgumentNullException(nameof(translator));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public async ValueTask<FileTranscriptionTranslationResult> TranslateAsync(
        string jobId,
        string targetLanguage,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        ArgumentException.ThrowIfNullOrWhiteSpace(targetLanguage);
        var normalizedTarget = targetLanguage.Trim();
        var job = jobs.Get(jobId);
        if (job is null
            || job.Status is not (FileTranscriptionJobStatus.Completed
                or FileTranscriptionJobStatus.PartiallyFailed)
            || string.IsNullOrWhiteSpace(job.FinalText))
        {
            return FileTranscriptionTranslationResult.ResultUnavailable;
        }

        job = UpdateTranslation(
            job,
            FileTranscriptionTranslationStatus.Pending,
            normalizedTarget,
            translatedText: null,
            errorCode: null);
        job = UpdateTranslation(
            job,
            FileTranscriptionTranslationStatus.Running,
            normalizedTarget,
            translatedText: null,
            errorCode: null);
        try
        {
            var translated = await translator.TranslateAsync(
                job.FinalText!,
                normalizedTarget,
                cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(translated))
            {
                throw new InvalidDataException("OpenAI returned an empty translation.");
            }

            _ = UpdateTranslation(
                job,
                FileTranscriptionTranslationStatus.Completed,
                normalizedTarget,
                translated.Trim(),
                errorCode: null);
            return FileTranscriptionTranslationResult.Succeeded;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            _ = UpdateTranslation(
                job,
                FileTranscriptionTranslationStatus.Failed,
                normalizedTarget,
                translatedText: null,
                FileTranscriptionErrorCode.TranslationFailure);
            return FileTranscriptionTranslationResult.Cancelled;
        }
        catch (FileTranscriptionTranslationUnavailableException)
        {
            _ = UpdateTranslation(
                job,
                FileTranscriptionTranslationStatus.Failed,
                normalizedTarget,
                translatedText: null,
                FileTranscriptionErrorCode.TranslationFailure);
            return FileTranscriptionTranslationResult.Unavailable;
        }
        catch
        {
            _ = UpdateTranslation(
                job,
                FileTranscriptionTranslationStatus.Failed,
                normalizedTarget,
                translatedText: null,
                FileTranscriptionErrorCode.TranslationFailure);
            return FileTranscriptionTranslationResult.Failed;
        }
    }

    private FileTranscriptionJob UpdateTranslation(
        FileTranscriptionJob job,
        FileTranscriptionTranslationStatus status,
        string targetLanguage,
        string? translatedText,
        FileTranscriptionErrorCode? errorCode)
    {
        var timestamp = Math.Max(
            job.UpdatedAtUnixMs,
            timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
        var updated = new FileTranscriptionJob(
            job.Id,
            job.SourcePath,
            job.DisplayName,
            job.Provider,
            job.Language,
            job.CreatedAtUnixMs,
            job.Status,
            job.DurationMs,
            job.Progress,
            job.RawText,
            job.FinalText,
            job.ErrorCode,
            job.ProviderMode,
            job.SegmentCount,
            job.SegmentCompleted,
            job.PartialFailureSummary,
            status,
            translatedText,
            targetLanguage,
            errorCode,
            timestamp,
            timestamp,
            job.CompletedAtUnixMs);
        if (!jobs.Update(updated))
        {
            throw new InvalidOperationException("The translation job no longer exists.");
        }
        return updated;
    }
}
