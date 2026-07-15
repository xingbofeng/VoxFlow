using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentContextSnapshot(
    ForegroundTargetSnapshot Target,
    string? SelectedText,
    IReadOnlyList<string> Warnings,
    string? VisibleText = null,
    string? OcrText = null,
    string? FocusedInputText = null,
    SelectionSnapshot? Selection = null)
{
    public const string UntrustedContextLabel = "untrusted_context";
}

public sealed record AgentContextReadResult(
    SelectionSnapshot? Selection,
    string? FocusedInputText,
    string? VisibleText,
    bool IsSecure = false);

public interface IAgentContextReader
{
    Task<AgentContextReadResult> ReadAsync(
        ForegroundTargetSnapshot target,
        CancellationToken cancellationToken);
}

public sealed record AgentVisualTextFallbackResult(string? Text, string? Warning);

/// <summary>Platform boundary for the strictly local visual fallback. It may
/// return text and a stable warning only: image bytes and image paths never
/// cross into Application, workflow persistence, prompts, or traces.</summary>
public interface IAgentVisualTextFallback
{
    Task<AgentVisualTextFallbackResult> ReadAsync(
        ForegroundTargetSnapshot target,
        string taskWorkspace,
        CancellationToken cancellationToken);
}

/// <summary>Captures only a bounded, untrusted snapshot of the frozen target.
/// User speech remains the sole trusted instruction for the Agent.</summary>
public sealed class AgentContextPipeline
{
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(2);
    public const int MinimumStructuredTextCharacters = 80;
    private readonly IAgentContextReader reader;
    private readonly IAgentVisualTextFallback? visualFallback;
    private readonly TimeSpan timeout;

    public AgentContextPipeline(
        IAgentContextReader reader,
        TimeSpan? timeout)
        : this(reader, visualFallback: null, timeout: timeout)
    {
    }

    public AgentContextPipeline(
        IAgentContextReader reader,
        IAgentVisualTextFallback? visualFallback = null,
        TimeSpan? timeout = null)
    {
        this.reader = reader ?? throw new ArgumentNullException(nameof(reader));
        this.visualFallback = visualFallback;
        this.timeout = timeout ?? DefaultTimeout;
        if (this.timeout <= TimeSpan.Zero || this.timeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }
    }

    public Task<AgentContextSnapshot> CaptureAsync(
        ForegroundTargetSnapshot target,
        CancellationToken cancellationToken) => CaptureAsync(
            target,
            taskWorkspace: null,
            cancellationToken: cancellationToken);

    public async Task<AgentContextSnapshot> CaptureAsync(
        ForegroundTargetSnapshot target,
        string? taskWorkspace,
        CancellationToken cancellationToken)
    {
        using var timeoutCancellation = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken, timeoutCancellation.Token);
        try
        {
            var result = await reader.ReadAsync(target, linked.Token).ConfigureAwait(false);
            if (result.IsSecure)
            {
                return new(target, null, ["context_secure"]);
            }
            var snapshot = new AgentContextSnapshot(
                target,
                result.Selection?.Text,
                Array.Empty<string>(),
                result.VisibleText,
                OcrText: null,
                result.FocusedInputText,
                result.Selection);
            if (visualFallback is null
                || string.IsNullOrWhiteSpace(taskWorkspace)
                || HasSufficientStructuredText(snapshot))
            {
                return snapshot;
            }

            var visual = await visualFallback.ReadAsync(
                target,
                taskWorkspace,
                linked.Token).ConfigureAwait(false);
            var warnings = string.IsNullOrWhiteSpace(visual.Warning)
                ? snapshot.Warnings
                : snapshot.Warnings.Append(visual.Warning).ToArray();
            return snapshot with
            {
                OcrText = string.IsNullOrWhiteSpace(visual.Text) ? null : visual.Text,
                Warnings = warnings,
            };
        }
        catch (OperationCanceledException) when (timeoutCancellation.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            return new(target, null, ["context_timeout"]);
        }
        catch (OperationCanceledException) { throw; }
        catch { return new(target, null, ["context_unavailable"]); }
    }

    private static bool HasSufficientStructuredText(AgentContextSnapshot context) =>
        new[] { context.SelectedText, context.FocusedInputText, context.VisibleText }
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Sum(value => value!.Length) >= MinimumStructuredTextCharacters;
}
