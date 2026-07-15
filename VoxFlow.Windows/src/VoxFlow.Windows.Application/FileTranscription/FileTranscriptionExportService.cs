using System.Globalization;
using System.Text;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public enum FileTranscriptionExportError
{
    ResultUnavailable,
    TranslationUnavailable,
    SegmentsUnavailable,
}

public sealed class FileTranscriptionExportException(
    FileTranscriptionExportError error)
    : Exception($"File transcription export failed ({error}).")
{
    public FileTranscriptionExportError Error { get; } = error;
}

public enum FileTranscriptionExportResult
{
    Saved,
    Cancelled,
}

public sealed record FileTranscriptionExportLabels(
    string OriginalHeading,
    string TranslationHeading);

public sealed record FileTranscriptionExportDocument
{
    public FileTranscriptionExportDocument(
        string suggestedFileName,
        string content,
        string extension)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(suggestedFileName);
        ArgumentNullException.ThrowIfNull(content);
        ArgumentException.ThrowIfNullOrWhiteSpace(extension);
        SuggestedFileName = suggestedFileName;
        Content = content;
        Extension = extension.TrimStart('.').ToLowerInvariant();
    }

    public string SuggestedFileName { get; }
    public string Content { get; }
    public string Extension { get; }
}

public interface IFileTranscriptionExportDestination
{
    ValueTask<FileTranscriptionExportResult> SaveAsync(
        FileTranscriptionExportDocument document,
        CancellationToken cancellationToken);
}

public sealed class FileTranscriptionExportService
{
    private static readonly HashSet<char> InvalidWindowsFileNameCharacters =
        new("<>:\"/\\|?*".Concat(Enumerable.Range(0, 32).Select(value => (char)value)));

    private readonly IFileTranscriptionSegmentRepository segments;
    private readonly IFileTranscriptionExportDestination destination;
    private readonly FileTranscriptionExportLabels labels;

    public FileTranscriptionExportService(
        IFileTranscriptionSegmentRepository segments,
        IFileTranscriptionExportDestination destination,
        FileTranscriptionExportLabels labels)
    {
        this.segments = segments ?? throw new ArgumentNullException(nameof(segments));
        this.destination = destination ?? throw new ArgumentNullException(nameof(destination));
        this.labels = labels ?? throw new ArgumentNullException(nameof(labels));
        ArgumentException.ThrowIfNullOrWhiteSpace(labels.OriginalHeading);
        ArgumentException.ThrowIfNullOrWhiteSpace(labels.TranslationHeading);
    }

    public ValueTask<FileTranscriptionExportResult> ExportAsync(
        FileTranscriptionJob job,
        FileTranscriptionExportFormat format,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(job);
        if (!Enum.IsDefined(format))
        {
            throw new ArgumentOutOfRangeException(nameof(format));
        }
        if (job.Status is not (FileTranscriptionJobStatus.Completed
            or FileTranscriptionJobStatus.PartiallyFailed)
            || string.IsNullOrWhiteSpace(job.FinalText))
        {
            throw new FileTranscriptionExportException(
                FileTranscriptionExportError.ResultUnavailable);
        }

        var document = BuildDocument(job, format);
        return destination.SaveAsync(document, cancellationToken);
    }

    private FileTranscriptionExportDocument BuildDocument(
        FileTranscriptionJob job,
        FileTranscriptionExportFormat format)
    {
        var name = SanitizeFileName(job.DisplayName);
        return format switch
        {
            FileTranscriptionExportFormat.Text => new(
                $"{name}.txt", job.FinalText!, "txt"),
            FileTranscriptionExportFormat.Markdown => new(
                $"{name}.md", Markdown(job.DisplayName, job.FinalText!), "md"),
            FileTranscriptionExportFormat.Srt => new(
                $"{name}.srt", BuildSrt(job.Id), "srt"),
            FileTranscriptionExportFormat.TranslatedText => new(
                $"{name}.translated.txt", RequireTranslation(job), "txt"),
            FileTranscriptionExportFormat.TranslatedMarkdown => new(
                $"{name}.translated.md",
                Markdown(job.DisplayName, RequireTranslation(job)),
                "md"),
            FileTranscriptionExportFormat.BilingualMarkdown => new(
                $"{name}.bilingual.md",
                BilingualMarkdown(job),
                "md"),
            _ => throw new ArgumentOutOfRangeException(nameof(format)),
        };
    }

    private string BilingualMarkdown(FileTranscriptionJob job) =>
        $"# {job.DisplayName}\n\n" +
        $"## {labels.OriginalHeading}\n\n{job.FinalText}\n\n" +
        $"## {labels.TranslationHeading}\n\n{RequireTranslation(job)}\n";

    private static string Markdown(string displayName, string text) =>
        $"# {displayName}\n\n{text}";

    private static string RequireTranslation(FileTranscriptionJob job)
    {
        if (job.TranslationStatus != FileTranscriptionTranslationStatus.Completed
            || string.IsNullOrWhiteSpace(job.TranslatedText))
        {
            throw new FileTranscriptionExportException(
                FileTranscriptionExportError.TranslationUnavailable);
        }
        return job.TranslatedText;
    }

    private string BuildSrt(string jobId)
    {
        var completed = segments.ListByJob(jobId)
            .Where(segment => segment.Status == FileTranscriptionSegmentStatus.Completed
                && !string.IsNullOrWhiteSpace(segment.Text))
            .OrderBy(segment => segment.Index)
            .ToArray();
        if (completed.Length == 0)
        {
            throw new FileTranscriptionExportException(
                FileTranscriptionExportError.SegmentsUnavailable);
        }

        return string.Join("\r\n\r\n", completed.Select((segment, index) =>
            $"{index + 1}\r\n{Timestamp(segment.StartMs)} --> {Timestamp(segment.EndMs)}\r\n{segment.Text}"));
    }

    private static string Timestamp(long milliseconds)
    {
        var hours = milliseconds / 3_600_000;
        var minutes = milliseconds % 3_600_000 / 60_000;
        var seconds = milliseconds % 60_000 / 1_000;
        var remainder = milliseconds % 1_000;
        return string.Create(
            CultureInfo.InvariantCulture,
            $"{hours:00}:{minutes:00}:{seconds:00},{remainder:000}");
    }

    private static string SanitizeFileName(string value)
    {
        var builder = new StringBuilder(value.Length);
        foreach (var character in value)
        {
            builder.Append(InvalidWindowsFileNameCharacters.Contains(character) ? '-' : character);
        }
        var sanitized = builder.ToString().Trim().TrimEnd('.', ' ');
        return string.IsNullOrWhiteSpace(sanitized) ? "transcription" : sanitized;
    }
}
