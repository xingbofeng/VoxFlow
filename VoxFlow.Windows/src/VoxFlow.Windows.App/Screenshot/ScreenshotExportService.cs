using System.Globalization;
using System.IO;
using System.Security;
using System.Windows;
using VoxFlow.Windows.App.Localization;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotExportStatus
{
    Saved,
    Cancelled,
    Failed,
}

public sealed record ScreenshotExportResult(
    ScreenshotExportStatus Status,
    string? Path,
    string? ErrorMessage);

public sealed record ScreenshotSaveDialogRequest(
    string Title,
    string Filter,
    string DefaultExtension,
    string DefaultFileName,
    bool AddExtension,
    bool OverwritePrompt);

public interface IScreenshotSaveDialog
{
    string? Show(ScreenshotSaveDialogRequest request);
}

public interface IScreenshotDefaultFileNameProvider
{
    string Create(CultureInfo culture);
}

public interface IScreenshotAtomicPngWriter
{
    Task WriteAsync(
        string path,
        ReadOnlyMemory<byte> pngBytes,
        CancellationToken cancellationToken);
}

public interface IScreenshotExportFileSystem
{
    Task WriteAndFlushAsync(
        string path,
        ReadOnlyMemory<byte> bytes,
        CancellationToken cancellationToken);

    bool FileExists(string path);

    void Replace(string sourcePath, string destinationPath);

    void Move(string sourcePath, string destinationPath);

    void DeleteIfExists(string path);
}

/// <summary>
/// The real Windows SaveFileDialog adapter. The injected owner keeps it modal to the active UI.
/// </summary>
public sealed class WindowsScreenshotSaveDialog(Func<Window?>? ownerProvider = null)
    : IScreenshotSaveDialog
{
    private readonly Func<Window?> ownerProvider = ownerProvider ?? (() => null);

    public string? Show(ScreenshotSaveDialogRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Title = request.Title,
            Filter = request.Filter,
            DefaultExt = request.DefaultExtension,
            FileName = request.DefaultFileName,
            AddExtension = request.AddExtension,
            OverwritePrompt = request.OverwritePrompt,
            CheckPathExists = true,
            ValidateNames = true,
        };
        var owner = ownerProvider();
        var accepted = owner is null
            ? dialog.ShowDialog()
            : dialog.ShowDialog(owner);
        return accepted == true ? dialog.FileName : null;
    }
}

public sealed class ScreenshotDefaultFileNameProvider : IScreenshotDefaultFileNameProvider
{
    private readonly Func<DateTimeOffset> localNow;
    private readonly Func<Guid> createId;

    public ScreenshotDefaultFileNameProvider(
        Func<DateTimeOffset>? localNow = null,
        Func<Guid>? createId = null)
    {
        this.localNow = localNow ?? (() => DateTimeOffset.Now);
        this.createId = createId ?? Guid.NewGuid;
    }

    public string Create(CultureInfo culture)
    {
        ArgumentNullException.ThrowIfNull(culture);
        var prefix = SanitizeFileNamePart(
            L10n.Localize("ScreenshotDefaultFileNamePrefix", culture));
        var timestamp = localNow().ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        var suffix = createId().ToString("N", CultureInfo.InvariantCulture)[..8];
        return $"{prefix}-{timestamp}-{suffix}.png";
    }

    private static string SanitizeFileNamePart(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var sanitized = new string(
            value.Where(character => !invalid.Contains(character)).ToArray())
            .Trim()
            .TrimEnd('.', ' ');
        return string.IsNullOrWhiteSpace(sanitized)
            ? "VoxFlow-Screenshot"
            : sanitized;
    }
}

/// <summary>
/// Writes a PNG through a same-directory temporary file and a final atomic replace or move.
/// </summary>
public sealed class AtomicScreenshotPngWriter : IScreenshotAtomicPngWriter
{
    private readonly IScreenshotExportFileSystem fileSystem;
    private readonly Func<Guid> createTemporaryId;

    public AtomicScreenshotPngWriter()
        : this(PhysicalScreenshotExportFileSystem.Instance, Guid.NewGuid)
    {
    }

    public AtomicScreenshotPngWriter(
        IScreenshotExportFileSystem fileSystem,
        Func<Guid>? createTemporaryId = null)
    {
        this.fileSystem = fileSystem ?? throw new ArgumentNullException(nameof(fileSystem));
        this.createTemporaryId = createTemporaryId ?? Guid.NewGuid;
    }

    public async Task WriteAsync(
        string path,
        ReadOnlyMemory<byte> pngBytes,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (pngBytes.IsEmpty)
        {
            throw new ArgumentException("The PNG payload cannot be empty.", nameof(pngBytes));
        }

        cancellationToken.ThrowIfCancellationRequested();
        var targetPath = Path.GetFullPath(path);
        var directory = Path.GetDirectoryName(targetPath)
            ?? throw new ArgumentException("The target path has no directory.", nameof(path));
        var fileName = Path.GetFileName(targetPath);
        var temporaryPath = Path.Combine(
            directory,
            $".{fileName}.{createTemporaryId():N}.tmp");

        try
        {
            await fileSystem.WriteAndFlushAsync(
                temporaryPath,
                pngBytes,
                cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            if (fileSystem.FileExists(targetPath))
            {
                fileSystem.Replace(temporaryPath, targetPath);
            }
            else
            {
                fileSystem.Move(temporaryPath, targetPath);
            }
        }
        catch
        {
            try
            {
                fileSystem.DeleteIfExists(temporaryPath);
            }
            catch (Exception exception) when (
                exception is IOException
                    or UnauthorizedAccessException
                    or SecurityException)
            {
                // Preserve the original save failure. Startup cleanup can remove a locked temp.
            }

            throw;
        }
    }

    private sealed class PhysicalScreenshotExportFileSystem : IScreenshotExportFileSystem
    {
        public static PhysicalScreenshotExportFileSystem Instance { get; } = new();

        public async Task WriteAndFlushAsync(
            string path,
            ReadOnlyMemory<byte> bytes,
            CancellationToken cancellationToken)
        {
            const int bufferSize = 81920;
            await using var stream = new FileStream(
                path,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize,
                FileOptions.Asynchronous | FileOptions.WriteThrough);
            await stream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
            await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
            stream.Flush(flushToDisk: true);
        }

        public bool FileExists(string path) => File.Exists(path);

        public void Replace(string sourcePath, string destinationPath)
        {
            try
            {
                File.Replace(
                    sourcePath,
                    destinationPath,
                    destinationBackupFileName: null,
                    ignoreMetadataErrors: true);
            }
            catch (PlatformNotSupportedException)
            {
                File.Move(sourcePath, destinationPath, overwrite: true);
            }
        }

        public void Move(string sourcePath, string destinationPath) =>
            File.Move(sourcePath, destinationPath);

        public void DeleteIfExists(string path) => File.Delete(path);
    }
}

/// <summary>
/// Download boundary only: it deliberately has no OCR, persistence, or history dependency.
/// </summary>
public sealed class ScreenshotExportService(
    IScreenshotSaveDialog dialog,
    IScreenshotAtomicPngWriter writer,
    IScreenshotDefaultFileNameProvider names)
{
    private readonly IScreenshotSaveDialog dialog = dialog
        ?? throw new ArgumentNullException(nameof(dialog));
    private readonly IScreenshotAtomicPngWriter writer = writer
        ?? throw new ArgumentNullException(nameof(writer));
    private readonly IScreenshotDefaultFileNameProvider names = names
        ?? throw new ArgumentNullException(nameof(names));

    public ScreenshotExportService()
        : this(
            new WindowsScreenshotSaveDialog(),
            new AtomicScreenshotPngWriter(),
            new ScreenshotDefaultFileNameProvider())
    {
    }

    public async Task<ScreenshotExportResult> DownloadAsync(
        ScreenshotRenderResult render,
        CultureInfo? culture = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(render);
        cancellationToken.ThrowIfCancellationRequested();
        var resolvedCulture = culture ?? CultureInfo.CurrentUICulture;

        try
        {
            var request = new ScreenshotSaveDialogRequest(
                L10n.Localize("ScreenshotSaveDialogTitle", resolvedCulture),
                L10n.Localize("ScreenshotPngFileFilter", resolvedCulture),
                DefaultExtension: ".png",
                DefaultFileName: names.Create(resolvedCulture),
                AddExtension: true,
                OverwritePrompt: true);
            var selectedPath = dialog.Show(request);
            if (string.IsNullOrWhiteSpace(selectedPath))
            {
                return new ScreenshotExportResult(
                    ScreenshotExportStatus.Cancelled,
                    Path: null,
                    ErrorMessage: null);
            }

            await writer.WriteAsync(
                selectedPath,
                render.PngBytes,
                cancellationToken).ConfigureAwait(false);
            return new ScreenshotExportResult(
                ScreenshotExportStatus.Saved,
                selectedPath,
                ErrorMessage: null);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or SecurityException
                or ArgumentException
                or InvalidOperationException
                or NotSupportedException)
        {
            return new ScreenshotExportResult(
                ScreenshotExportStatus.Failed,
                Path: null,
                L10n.Localize("ScreenshotSaveFailed", resolvedCulture));
        }
    }
}
