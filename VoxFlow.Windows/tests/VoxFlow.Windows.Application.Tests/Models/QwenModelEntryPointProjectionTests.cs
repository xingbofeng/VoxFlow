using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests.Models;

public sealed class QwenModelEntryPointProjectionTests
{
    [Fact]
    public void Selection_and_deletion_update_home_settings_and_menu_from_one_snapshot()
    {
        var store = new VoxFlowStateStore();
        using var projection = new QwenModelEntryPointProjection(store);
        var synchronizer = new QwenModelStateSynchronizer(store);
        var manifest = Manifest(new QwenRuntimePublicationGate(true, null));
        var ready = State(manifest, ModelInstallPhase.Ready);

        synchronizer.Publish(manifest, ready);
        synchronizer.Select(manifest.Id);

        var selected = projection.Current;
        Assert.Same(selected.Home, selected.Settings);
        Assert.Same(selected.Home, selected.Menu);
        var card = Assert.Single(selected.Home);
        Assert.True(card.IsSelected);
        Assert.True(card.IsReady);
        Assert.True(card.IsSelectable);

        synchronizer.Publish(manifest, State(manifest, ModelInstallPhase.NotDownloaded));

        var deleted = projection.Current;
        Assert.Same(deleted.Home, deleted.Settings);
        Assert.Same(deleted.Home, deleted.Menu);
        card = Assert.Single(deleted.Home);
        Assert.False(card.IsSelected);
        Assert.False(card.IsReady);
        Assert.False(card.IsSelectable);
        Assert.Equal(ModelInstallPhase.NotDownloaded, card.Phase);
    }

    [Fact]
    public void Blocked_provenance_is_never_selectable_even_if_a_stale_row_says_ready()
    {
        var store = new VoxFlowStateStore();
        using var projection = new QwenModelEntryPointProjection(store);
        var synchronizer = new QwenModelStateSynchronizer(store);
        var manifest = Manifest(new QwenRuntimePublicationGate(false, "blocked"));

        synchronizer.Publish(manifest, State(manifest, ModelInstallPhase.Ready));

        var card = Assert.Single(projection.Current.Menu);
        Assert.False(card.IsSelectable);
        Assert.False(card.IsReady);
        Assert.Equal("runtime_provenance_blocked", card.ErrorCode);
        Assert.Throws<InvalidOperationException>(() => synchronizer.Select(manifest.Id));
    }

    private static ModelInstallRecord State(
        QwenModelManifest manifest,
        ModelInstallPhase phase) => new(
            manifest.Id,
            manifest.ModelRevision,
            phase,
            phase == ModelInstallPhase.NotDownloaded ? 0 : manifest.TotalBytes,
            manifest.TotalBytes,
            phase == ModelInstallPhase.NotDownloaded ? null : @"C:\Models\qwen",
            null);

    private static QwenModelManifest Manifest(QwenRuntimePublicationGate gate)
    {
        byte[] bytes = [1, 2];
        return new QwenModelManifest(
            "qwen3-asr-0.6b",
            "Qwen 0.6B",
            QwenVariant.Qwen06B,
            "revision",
            "runtime",
            bytes.Length,
            [new QwenModelFile(
                "model.bin",
                new Uri("https://models.invalid/model.bin"),
                bytes.Length,
                Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant())],
            gate);
    }
}
