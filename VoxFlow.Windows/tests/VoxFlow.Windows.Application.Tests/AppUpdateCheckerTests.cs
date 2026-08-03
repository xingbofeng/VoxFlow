using VoxFlow.Windows.Application.Update;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AppUpdateCheckerTests
{
    [Fact]
    public async Task CheckAsync_reports_update_available_when_remote_is_newer()
    {
        var checker = new AppUpdateChecker(_ => ValueTask.FromResult<AppUpdateChecker.RemoteReleaseInfo?>(
            new AppUpdateChecker.RemoteReleaseInfo("v2.1.0", "https://example.test/release")));

        var result = await checker.CheckAsync("1.0.0");

        Assert.Equal(AppUpdateAvailability.UpdateAvailable, result.Availability);
        Assert.Equal("2.1.0", result.LatestVersion);
        Assert.Equal("1.0.0", result.CurrentVersion);
        Assert.True(result.CanOpenReleasePage);
        Assert.Contains("2.1.0", result.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task CheckAsync_reports_up_to_date_when_versions_match()
    {
        var checker = new AppUpdateChecker(_ => ValueTask.FromResult<AppUpdateChecker.RemoteReleaseInfo?>(
            new AppUpdateChecker.RemoteReleaseInfo("v1.2.3", "https://example.test/release")));

        var result = await checker.CheckAsync("1.2.3");

        Assert.Equal(AppUpdateAvailability.UpToDate, result.Availability);
        Assert.Equal("1.2.3", result.LatestVersion);
    }

    [Fact]
    public async Task CheckAsync_reports_failed_when_remote_missing()
    {
        var checker = new AppUpdateChecker(_ => ValueTask.FromResult<AppUpdateChecker.RemoteReleaseInfo?>(null));

        var result = await checker.CheckAsync("1.0.0");

        Assert.Equal(AppUpdateAvailability.Failed, result.Availability);
        Assert.Null(result.LatestVersion);
        Assert.True(result.CanOpenReleasePage);
    }

    [Theory]
    [InlineData("1.0.0", "1.0.1", -1)]
    [InlineData("1.2.0", "1.2.0", 0)]
    [InlineData("2.0.0", "1.9.9", 1)]
    [InlineData("v1.0", "1.0.0", 0)]
    public void CompareVersions_orders_semver_like_tags(string left, string right, int expectedSign)
    {
        var cmp = AppUpdateChecker.CompareVersions(left, right);
        Assert.Equal(Math.Sign(expectedSign), Math.Sign(cmp));
    }
}
