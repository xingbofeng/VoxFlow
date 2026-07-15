using System.Text.Json;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Models;

public static class WindowsQwenManifestLoader
{
    public static QwenModelCatalog Load(string provenancePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(provenancePath);
        using var stream = File.OpenRead(provenancePath);
        var raw = JsonSerializer.Deserialize<RawProvenance>(stream, SerializerOptions)
            ?? throw new InvalidDataException("The Windows Qwen provenance is empty.");

        if (raw.SchemaVersion != 1
            || raw.Runtime is null
            || string.IsNullOrWhiteSpace(raw.Runtime.UpstreamRevision)
            || raw.Models is null)
        {
            throw new InvalidDataException("The Windows Qwen provenance shape is invalid.");
        }

        var validationStatus = raw.Runtime.WindowsValidation?.Status;
        if (raw.Publishable
            && !string.Equals(validationStatus, "passed", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                "Windows Qwen provenance cannot be publishable while validation is blocked.");
        }

        var gate = new QwenRuntimePublicationGate(
            raw.Publishable,
            raw.Publishable ? null : raw.PublicationBlocker);
        var models = raw.Models
            .Select(model => CreateManifest(model, raw.Runtime.UpstreamRevision, gate))
            .OrderBy(model => model.Variant)
            .ToArray();

        if (models.Length != 2
            || models.Select(model => model.Variant).Distinct().Count() != 2)
        {
            throw new InvalidDataException(
                "Windows Qwen provenance must contain exactly the approved 0.6B and 1.7B models.");
        }

        return new QwenModelCatalog(raw.Runtime.UpstreamRevision, gate, models);
    }

    private static QwenModelManifest CreateManifest(
        RawModel raw,
        string runtimeRevision,
        QwenRuntimePublicationGate gate)
    {
        if (raw.Files is null || string.IsNullOrWhiteSpace(raw.RepositoryRevision))
        {
            throw new InvalidDataException("A Windows Qwen model record is incomplete.");
        }

        var variant = raw.Id switch
        {
            "qwen3-asr-0.6b" => QwenVariant.Qwen06B,
            "qwen3-asr-1.7b" => QwenVariant.Qwen17B,
            _ => throw new InvalidDataException($"Unsupported Windows Qwen model id: {raw.Id}."),
        };

        if (!string.Equals(raw.UserVisibleName, variant.DisplayName(), StringComparison.Ordinal)
            || raw.Format?.Contains("MLX", StringComparison.OrdinalIgnoreCase) == true)
        {
            throw new InvalidDataException("Windows Qwen provenance contains an invalid model identity or format.");
        }

        try
        {
            var files = raw.Files.Select(file => new QwenModelFile(
                file.Name ?? string.Empty,
                new Uri(file.Url ?? string.Empty, UriKind.Absolute),
                file.Bytes,
                file.Sha256 ?? string.Empty)).ToArray();
            return new QwenModelManifest(
                raw.Id!,
                raw.UserVisibleName!,
                variant,
                raw.RepositoryRevision,
                runtimeRevision,
                raw.TotalBytes,
                files,
                gate);
        }
        catch (Exception exception) when (exception is ArgumentException or UriFormatException)
        {
            throw new InvalidDataException("A Windows Qwen model file record is invalid.", exception);
        }
    }

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private sealed record RawProvenance(
        int SchemaVersion,
        bool Publishable,
        string? PublicationBlocker,
        RawRuntime? Runtime,
        RawModel[]? Models);

    private sealed record RawRuntime(
        string UpstreamRevision,
        RawWindowsValidation? WindowsValidation);

    private sealed record RawWindowsValidation(string? Status);

    private sealed record RawModel(
        string? Id,
        string? UserVisibleName,
        string? RepositoryRevision,
        string? Format,
        long TotalBytes,
        RawFile[]? Files);

    private sealed record RawFile(
        string? Name,
        string? Url,
        long Bytes,
        string? Sha256);
}
