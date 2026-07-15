using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Models;

public sealed record QwenRuntimePublicationGate(bool IsPublishable, string? Blocker);

public sealed record QwenModelFile
{
    public QwenModelFile(string name, Uri source, long bytes, string sha256)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(source);
        ArgumentException.ThrowIfNullOrWhiteSpace(sha256);

        if (Path.IsPathRooted(name)
            || name.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries)
                .Any(segment => segment == ".."))
        {
            throw new ArgumentException("Model file names must be safe relative paths.", nameof(name));
        }

        if (!source.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Model files must use HTTPS.", nameof(source));
        }

        if (bytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(bytes), "Model file size must be positive.");
        }

        if (sha256.Length != 64 || !sha256.All(Uri.IsHexDigit))
        {
            throw new ArgumentException("Model SHA-256 must contain 64 hexadecimal characters.", nameof(sha256));
        }

        Name = name.Replace('\\', '/');
        Source = source;
        Bytes = bytes;
        Sha256 = sha256.ToLowerInvariant();
    }

    public string Name { get; }

    public Uri Source { get; }

    public long Bytes { get; }

    public string Sha256 { get; }
}

public sealed record QwenModelManifest
{
    public QwenModelManifest(
        string id,
        string displayName,
        QwenVariant variant,
        string modelRevision,
        string runtimeRevision,
        long totalBytes,
        IReadOnlyList<QwenModelFile> files,
        QwenRuntimePublicationGate runtimeGate)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentException.ThrowIfNullOrWhiteSpace(displayName);
        ArgumentException.ThrowIfNullOrWhiteSpace(modelRevision);
        ArgumentException.ThrowIfNullOrWhiteSpace(runtimeRevision);
        ArgumentNullException.ThrowIfNull(files);
        ArgumentNullException.ThrowIfNull(runtimeGate);

        if (files.Count == 0 || totalBytes <= 0 || files.Sum(file => file.Bytes) != totalBytes)
        {
            throw new ArgumentException("Model file sizes must equal the manifest total.", nameof(files));
        }

        Id = id;
        DisplayName = displayName;
        Variant = variant;
        ModelRevision = modelRevision;
        RuntimeRevision = runtimeRevision;
        RuntimeVersion = $"qwen-asr@{runtimeRevision}";
        TotalBytes = totalBytes;
        Files = files.ToArray();
        RuntimeGate = runtimeGate;
    }

    public string Id { get; }

    public string DisplayName { get; }

    public QwenVariant Variant { get; }

    public string ModelRevision { get; }

    public string RuntimeRevision { get; }

    public string RuntimeVersion { get; }

    public long TotalBytes { get; }

    public IReadOnlyList<QwenModelFile> Files { get; }

    public QwenRuntimePublicationGate RuntimeGate { get; }
}

public sealed record QwenModelCatalog(
    string RuntimeRevision,
    QwenRuntimePublicationGate RuntimeGate,
    IReadOnlyList<QwenModelManifest> Models);
