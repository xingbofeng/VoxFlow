using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Infrastructure.Screenshots;
using VoxFlow.Windows.Platform.Input;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class CompositionRootWorkflowRecoveryTests
{
    [Fact]
    public async Task Composition_root_runs_screenshot_retention_without_touching_save_as_files()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        var flags = WindowsInteractiveFeatureFlags.Disabled;
        new VoxFlowDatabaseMigrator(
        [
            .. InteractiveFeatureMigrationCatalog.For(flags),
            .. ScreenshotMigrationCatalog.All(),
        ]).Migrate(databasePath);
        var store = new FileScreenshotAssetStore(directory.Path);
        var assets = await store.SaveAsync(
            new ScreenshotAssetWriteRequest(
                "expired-screenshot",
                Png(1),
                Png(2),
                Png(3)),
            CancellationToken.None);
        using (var runner = new SqliteTransactionRunner(
            new SqliteConnectionFactory(databasePath, pooling: false)))
        {
            var records = new SqliteScreenshotRecordRepository(runner);
            var createdAt = DateTimeOffset.UtcNow.AddDays(-40);
            records.Add(new ScreenshotRecord(
                "expired-screenshot",
                assets.OriginalImagePath,
                assets.RenderedImagePath,
                assets.ThumbnailPath,
                800,
                600,
                assets.RenderedFileSizeBytes,
                "expired",
                createdAt));
            Assert.True(records.SoftDelete(
                "expired-screenshot",
                DateTimeOffset.UtcNow.AddDays(-31)));
        }
        var saveAsPath = Path.Combine(directory.Path, "user-save-as.png");
        await File.WriteAllBytesAsync(saveAsPath, Png(9));

        var rootType = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.WindowsAppCompositionRoot");
        Assert.NotNull(rootType);
        dynamic root = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            databasePath,
            new DisabledRefiner(),
            flags)!);
        using ((IDisposable)root)
        {
            var result = Assert.IsType<ScreenshotMaintenanceResult>(
                root.ScreenshotMaintenanceResult);
            var records = Assert.IsAssignableFrom<IScreenshotRecordRepository>(
                root.ScreenshotRecords);
            Assert.Equal(1, result.PurgedRecordCount);
            Assert.Null(records.Get("expired-screenshot", includeDeleted: true));
            Assert.All(
                assets.AllRelativePaths,
                path => Assert.False(File.Exists(store.ResolveAbsolutePath(path))));
            Assert.True(File.Exists(saveAsPath));
        }
    }

    [Fact]
    public void Enabled_composition_root_interrupts_active_workflow_tasks_on_startup()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        var flags = new WindowsInteractiveFeatureFlags(
            selectionTransformEnabled: true,
            builtinAgentEnabled: true);
        new VoxFlowDatabaseMigrator(
            InteractiveFeatureMigrationCatalog.For(flags))
            .Migrate(databasePath);
        using (var runner = new SqliteTransactionRunner(
            new SqliteConnectionFactory(databasePath, pooling: false)))
        {
            new SqliteWorkflowTaskRepository(runner).Create(new WorkflowTaskRecord(
                "active-agent",
                WorkflowTaskKind.AgentCompose,
                WorkflowTaskStage.WaitingForUser,
                WorkflowTaskStatus.Running,
                Guid.NewGuid(),
                rawText: "帮我做",
                partialText: "等待回答",
                finalText: null,
                providerId: "openai",
                model: "gpt-test",
                targetJson: null,
                contextJson: null,
                traceJson: null,
                outputJson: null,
                failureJson: null,
                warningsJson: null,
                createdAtUnixMs: 100,
                updatedAtUnixMs: 100,
                completedAtUnixMs: null));
        }

        var rootType = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.WindowsAppCompositionRoot");
        Assert.NotNull(rootType);
        dynamic root = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            databasePath,
            new DisabledRefiner(),
            flags)!);
        using ((IDisposable)root)
        {
            var repository = Assert.IsAssignableFrom<IWorkflowTaskRepository>(
                root.WorkflowTasks);
            var recovered = Assert.IsType<WorkflowTaskRecord>(
                repository.Get("active-agent"));
            Assert.Equal(WorkflowTaskStatus.Interrupted, recovered.Status);
            Assert.Equal("等待回答", recovered.PartialText);
            Assert.NotNull(recovered.CompletedAtUnixMs);
        }
    }

    [Fact]
    public async Task Enabled_composition_root_loads_the_persisted_unique_hotkey_projection()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        var flags = new WindowsInteractiveFeatureFlags(
            selectionTransformEnabled: true,
            builtinAgentEnabled: true);
        new VoxFlowDatabaseMigrator(
            InteractiveFeatureMigrationCatalog.For(flags))
            .Migrate(databasePath);
        var settings = InteractiveHotkeySettingsDocument.Default with
        {
            SelectionSummary = null,
        };
        using (var runner = new SqliteTransactionRunner(
            new SqliteConnectionFactory(databasePath, pooling: false)))
        {
            await new SqliteInteractiveHotkeySettingsStore(runner)
                .SaveAsync(settings, CancellationToken.None);
        }

        var rootType = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.WindowsAppCompositionRoot");
        Assert.NotNull(rootType);
        dynamic root = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            databasePath,
            new DisabledRefiner(),
            flags)!);
        using ((IDisposable)root)
        {
            var bindings = Assert.IsType<InteractiveHotkeyBindingSet>(
                root.InteractiveHotkeyBindings);
            Assert.Null(bindings.SelectionSummary);
            Assert.NotNull(root.InteractiveHotkeyRoute);
            Assert.IsAssignableFrom<IInteractiveHotkeySettingsStore>(
                root.InteractiveHotkeySettingsStore);
        }
    }

    private sealed class DisabledRefiner : IStreamingTextRefiner
    {
        public ValueTask<LlmRefinerAvailability> GetAvailabilityAsync(
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(LlmRefinerAvailability.Disabled);

        public async IAsyncEnumerable<string> RefineAsync(
            string text,
            [System.Runtime.CompilerServices.EnumeratorCancellation]
            CancellationToken cancellationToken)
        {
            await Task.CompletedTask;
            yield break;
        }
    }

    private static byte[] Png(byte marker) =>
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, marker];
}
