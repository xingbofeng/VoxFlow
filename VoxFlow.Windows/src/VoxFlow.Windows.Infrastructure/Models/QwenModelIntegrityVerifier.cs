using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;

namespace VoxFlow.Windows.Infrastructure.Models;

public sealed record ModelIntegrityResult(
    bool IsValid,
    string? ErrorCode,
    string? FileName);

public sealed class QwenModelIntegrityVerifier
{
    public async Task<ModelIntegrityResult> VerifyAsync(
        QwenModelManifest manifest,
        string payloadRoot,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        ArgumentException.ThrowIfNullOrWhiteSpace(payloadRoot);
        var fullPayloadRoot = Path.GetFullPath(payloadRoot);

        foreach (var file in manifest.Files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var path = ResolvePayloadPath(fullPayloadRoot, file.Name);
            if (!File.Exists(path))
            {
                return new ModelIntegrityResult(false, "missing_file", file.Name);
            }

            if (new FileInfo(path).Length != file.Bytes)
            {
                return new ModelIntegrityResult(false, "size_mismatch", file.Name);
            }

            await using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            var digest = await SHA256.HashDataAsync(stream, cancellationToken)
                .ConfigureAwait(false);
            if (!Convert.ToHexString(digest).Equals(file.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                return new ModelIntegrityResult(false, "sha256_mismatch", file.Name);
            }
        }

        return new ModelIntegrityResult(true, null, null);
    }

    private static string ResolvePayloadPath(string payloadRoot, string relativeName)
    {
        var path = Path.GetFullPath(Path.Combine(
            payloadRoot,
            relativeName.Replace('/', Path.DirectorySeparatorChar)));
        var rootWithSeparator = payloadRoot.EndsWith(Path.DirectorySeparatorChar)
            ? payloadRoot
            : payloadRoot + Path.DirectorySeparatorChar;
        if (!path.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Model file escapes the payload directory.");
        }

        return path;
    }
}
