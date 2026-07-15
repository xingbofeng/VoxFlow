using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace VoxFlow.Windows.Application.Update;

public enum AppUpdateAvailability
{
    Unknown,
    UpToDate,
    UpdateAvailable,
    Failed,
}

public sealed record AppUpdateCheckResult(
    AppUpdateAvailability Availability,
    string CurrentVersion,
    string? LatestVersion,
    string? ReleaseUrl,
    string Message,
    DateTimeOffset CheckedAtUtc)
{
    public bool CanOpenReleasePage =>
        !string.IsNullOrWhiteSpace(ReleaseUrl)
        && Uri.TryCreate(ReleaseUrl, UriKind.Absolute, out _);
}

public interface IAppUpdateChecker
{
    ValueTask<AppUpdateCheckResult> CheckAsync(
        string currentVersion,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Compares the running app version against the public GitHub latest release tag.
/// Network access is injected so tests drive the real comparison path without HTTP.
/// </summary>
public sealed class AppUpdateChecker : IAppUpdateChecker
{
    public const string DefaultLatestReleaseApi =
        "https://api.github.com/repos/xingbofeng/VoxFlow/releases/latest";

    public const string DefaultReleasePage =
        "https://github.com/xingbofeng/VoxFlow/releases/latest";

    private static readonly Regex VersionCore = new(
        @"(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.(\d+))?",
        RegexOptions.Compiled);

    private readonly Func<CancellationToken, ValueTask<RemoteReleaseInfo?>> fetchLatest;
    private readonly TimeProvider timeProvider;

    public AppUpdateChecker(
        Func<CancellationToken, ValueTask<RemoteReleaseInfo?>> fetchLatest,
        TimeProvider? timeProvider = null)
    {
        this.fetchLatest = fetchLatest ?? throw new ArgumentNullException(nameof(fetchLatest));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public static AppUpdateChecker CreateHttp(
        HttpClient? httpClient = null,
        string? latestReleaseApiUrl = null,
        TimeProvider? timeProvider = null)
    {
        var client = httpClient ?? CreateDefaultClient();
        var url = string.IsNullOrWhiteSpace(latestReleaseApiUrl)
            ? DefaultLatestReleaseApi
            : latestReleaseApiUrl.Trim();
        return new AppUpdateChecker(
            async cancellationToken =>
            {
                using var response = await client
                    .GetAsync(url, cancellationToken)
                    .ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    return null;
                }

                var payload = await response.Content
                    .ReadFromJsonAsync<GitHubReleasePayload>(
                        cancellationToken: cancellationToken)
                    .ConfigureAwait(false);
                if (payload is null || string.IsNullOrWhiteSpace(payload.TagName))
                {
                    return null;
                }

                return new RemoteReleaseInfo(
                    payload.TagName,
                    string.IsNullOrWhiteSpace(payload.HtmlUrl)
                        ? DefaultReleasePage
                        : payload.HtmlUrl!);
            },
            timeProvider);
    }

    public async ValueTask<AppUpdateCheckResult> CheckAsync(
        string currentVersion,
        CancellationToken cancellationToken = default)
    {
        var current = string.IsNullOrWhiteSpace(currentVersion) ? "0.0.0" : currentVersion.Trim();
        var now = timeProvider.GetUtcNow();
        try
        {
            var remote = await fetchLatest(cancellationToken).ConfigureAwait(false);
            if (remote is null || string.IsNullOrWhiteSpace(remote.TagName))
            {
                return new AppUpdateCheckResult(
                    AppUpdateAvailability.Failed,
                    current,
                    null,
                    DefaultReleasePage,
                    "Unable to read the latest release metadata.",
                    now);
            }

            var latest = NormalizeTag(remote.TagName);
            var comparison = CompareVersions(current, latest);
            if (comparison < 0)
            {
                return new AppUpdateCheckResult(
                    AppUpdateAvailability.UpdateAvailable,
                    current,
                    latest,
                    remote.ReleaseUrl ?? DefaultReleasePage,
                    $"A newer version is available: {latest}.",
                    now);
            }

            return new AppUpdateCheckResult(
                AppUpdateAvailability.UpToDate,
                current,
                latest,
                remote.ReleaseUrl ?? DefaultReleasePage,
                $"You are on the latest version ({latest}).",
                now);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            return new AppUpdateCheckResult(
                AppUpdateAvailability.Failed,
                current,
                null,
                DefaultReleasePage,
                "Update check failed: " + exception.Message,
                now);
        }
    }

    public static int CompareVersions(string left, string right)
    {
        var a = Parse(left);
        var b = Parse(right);
        for (var i = 0; i < 4; i++)
        {
            var delta = a[i].CompareTo(b[i]);
            if (delta != 0)
            {
                return delta;
            }
        }

        return 0;
    }

    public static string NormalizeTag(string tag)
    {
        ArgumentNullException.ThrowIfNull(tag);
        var trimmed = tag.Trim();
        if (trimmed.StartsWith("v", StringComparison.OrdinalIgnoreCase))
        {
            trimmed = trimmed[1..];
        }

        var match = VersionCore.Match(trimmed);
        return match.Success ? match.Value : trimmed;
    }

    private static int[] Parse(string version)
    {
        var match = VersionCore.Match(version ?? string.Empty);
        if (!match.Success)
        {
            return [0, 0, 0, 0];
        }

        int Part(int group) => match.Groups[group].Success
            && int.TryParse(
                match.Groups[group].Value,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var value)
                ? value
                : 0;

        return [Part(1), Part(2), Part(3), Part(4)];
    }

    private static HttpClient CreateDefaultClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("VoxFlow-Windows-UpdateCheck/1.0");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    public sealed record RemoteReleaseInfo(string TagName, string? ReleaseUrl);

    private sealed class GitHubReleasePayload
    {
        [JsonPropertyName("tag_name")]
        public string? TagName { get; set; }

        [JsonPropertyName("html_url")]
        public string? HtmlUrl { get; set; }
    }
}
