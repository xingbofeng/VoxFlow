using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public enum AgentComposeExecutionStatus
{
    Completed,
    ProviderUnavailable,
    Failed,
}

public sealed record AgentComposeExecutionResult(
    AgentComposeExecutionStatus Status,
    BuiltinAgentSidecarRunOutcome? SidecarOutcome = null)
{
    public bool Succeeded => Status == AgentComposeExecutionStatus.Completed;
}

/// <summary>
/// The bridge between an Agent ASR final and the bundled Rust runtime. The
/// provider resolver is the only point that decrypts DPAPI credentials; this
/// service immediately serializes the request to the sidecar stdin and never
/// exposes a credential through its result or callbacks.
/// </summary>
public interface IAgentComposeExecutionService
{
    Task<AgentComposeExecutionResult> ExecuteWithBuiltinToolsAsync(
        string taskId,
        string voiceInstruction,
        AgentContextSnapshot context,
        string workspaceDirectory,
        IHistoryStore? history,
        Func<BuiltinAgentSidecarEvent, Task> onEvent,
        CancellationToken cancellationToken);
}

public sealed class AgentComposeExecutionService : IAgentComposeExecutionService
{
    private readonly IDefaultLlmProviderResolver providerResolver;
    private readonly AgentComposePromptBuilder promptBuilder;
    private readonly BuiltinAgentSidecarRunner sidecarRunner;
    private readonly IAgentClipboardTextGateway? clipboard;
    private readonly IAgentKeyboardGatewayFactory? keyboard;
    private readonly IAgentUrlLauncher? urlLauncher;
    private readonly IAgentTextFieldGatewayFactory? textField;
    private readonly IAgentHttpRequestClient? httpClient;
    private readonly IAgentWebFetchClient? webFetchClient;
    private readonly IAgentWebSearchClient? webSearchClient;
    private readonly IAgentUserResponsePresenter? responsePresenter;
    private readonly IAgentQuestionPresenter? questionPresenter;

    public AgentComposeExecutionService(
        IDefaultLlmProviderResolver providerResolver,
        AgentComposePromptBuilder promptBuilder,
        BuiltinAgentSidecarRunner sidecarRunner,
        IAgentClipboardTextGateway? clipboard = null,
        IAgentKeyboardGatewayFactory? keyboard = null,
        IAgentUrlLauncher? urlLauncher = null,
        IAgentTextFieldGatewayFactory? textField = null,
        IAgentHttpRequestClient? httpClient = null,
        IAgentWebFetchClient? webFetchClient = null,
        IAgentWebSearchClient? webSearchClient = null,
        IAgentUserResponsePresenter? responsePresenter = null,
        IAgentQuestionPresenter? questionPresenter = null)
    {
        this.providerResolver = providerResolver ?? throw new ArgumentNullException(nameof(providerResolver));
        this.promptBuilder = promptBuilder ?? throw new ArgumentNullException(nameof(promptBuilder));
        this.sidecarRunner = sidecarRunner ?? throw new ArgumentNullException(nameof(sidecarRunner));
        this.clipboard = clipboard;
        this.keyboard = keyboard;
        this.urlLauncher = urlLauncher;
        this.textField = textField;
        this.httpClient = httpClient;
        this.webFetchClient = webFetchClient;
        this.webSearchClient = webSearchClient;
        this.responsePresenter = responsePresenter;
        this.questionPresenter = questionPresenter;
    }

    public async Task<AgentComposeExecutionResult> ExecuteAsync(
        string taskId,
        string voiceInstruction,
        AgentContextSnapshot context,
        string workspaceDirectory,
        Func<BuiltinAgentSidecarEvent, Task> onEvent,
        Func<AgentToolCall, CancellationToken, Task<AgentToolResult>> executeTool,
        CancellationToken cancellationToken)
    {
        var provider = await providerResolver.ResolveDefaultAsync(cancellationToken)
            .ConfigureAwait(false);
        if (provider is null)
        {
            return new(AgentComposeExecutionStatus.ProviderUnavailable);
        }

        try
        {
            var request = promptBuilder.BuildRequest(
                taskId,
                voiceInstruction,
                provider,
                context,
                workspaceDirectory);
            var outcome = await sidecarRunner.RunAsync(
                    request,
                    onEvent,
                    executeTool,
                    cancellationToken)
                .ConfigureAwait(false);
            return new(outcome.Succeeded
                    ? AgentComposeExecutionStatus.Completed
                    : AgentComposeExecutionStatus.Failed,
                outcome);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return new(AgentComposeExecutionStatus.Failed);
        }
    }

    /// <summary>
    /// Runs the bundled Agent against the host tools that are currently
    /// implemented for a managed workspace.  The file host is created once per
    /// task so read-before-write state cannot leak between Agent runs.
    /// </summary>
    public Task<AgentComposeExecutionResult> ExecuteWithBuiltinFileToolsAsync(
        string taskId,
        string voiceInstruction,
        AgentContextSnapshot context,
        string workspaceDirectory,
        Func<BuiltinAgentSidecarEvent, Task> onEvent,
        CancellationToken cancellationToken)
        => ExecuteWithBuiltinToolsAsync(taskId, voiceInstruction, context,
            workspaceDirectory, history: null, onEvent, cancellationToken);

    /// <summary>Runs the approved workspace and retained-history tools for a
    /// task. Passing no history keeps search_transcriptions explicitly
    /// unavailable rather than broadening access to another data store.</summary>
    public Task<AgentComposeExecutionResult> ExecuteWithBuiltinToolsAsync(
        string taskId,
        string voiceInstruction,
        AgentContextSnapshot context,
        string workspaceDirectory,
        IHistoryStore? history,
        Func<BuiltinAgentSidecarEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        var fileHost = new BuiltinAgentFileToolHost(
            workspaceDirectory,
            history: history,
            authorization: new AgentToolAuthorizationPolicy(voiceInstruction));
        var handlers = new Dictionary<string, Func<AgentToolCall, CancellationToken, Task<AgentToolResult>>>(
            StringComparer.Ordinal)
        {
            ["read_file"] = fileHost.ExecuteAsync,
            ["write_file"] = fileHost.ExecuteAsync,
            ["edit_file"] = fileHost.ExecuteAsync,
            ["notebook_edit"] = fileHost.ExecuteAsync,
            ["list_files"] = fileHost.ExecuteAsync,
            ["glob_files"] = fileHost.ExecuteAsync,
            ["grep_files"] = fileHost.ExecuteAsync,
            ["search_transcriptions"] = fileHost.ExecuteAsync,
        };

        if (clipboard is not null)
        {
            var clipboardHost = new BuiltinAgentClipboardToolHost(clipboard);
            handlers["clipboard"] = clipboardHost.ExecuteAsync;
        }
        if (keyboard is not null)
        {
            var keyboardHost = new BuiltinAgentKeyboardToolHost(keyboard.Create(context.Target));
            handlers["keyboard"] = keyboardHost.ExecuteAsync;
        }
        if (urlLauncher is not null)
        {
            var openUrlHost = new BuiltinAgentOpenUrlToolHost(
                new AgentToolAuthorizationPolicy(voiceInstruction), urlLauncher);
            handlers["open_url"] = openUrlHost.ExecuteAsync;
        }
        if (textField is not null)
        {
            var textFieldHost = new BuiltinAgentTextFieldToolHost(
                context, textField.Create(context.Selection));
            handlers["text_field"] = textFieldHost.ExecuteAsync;
        }
        if (httpClient is not null)
        {
            var httpHost = new BuiltinAgentHttpRequestToolHost(
                new AgentToolAuthorizationPolicy(voiceInstruction), httpClient);
            handlers["http_request"] = httpHost.ExecuteAsync;
        }
        if (webFetchClient is not null)
        {
            var webFetchHost = new BuiltinAgentWebFetchToolHost(
                new AgentToolAuthorizationPolicy(voiceInstruction), webFetchClient);
            handlers["web_fetch"] = webFetchHost.ExecuteAsync;
        }
        if (webSearchClient is not null)
        {
            var webSearchHost = new BuiltinAgentWebSearchToolHost(webSearchClient);
            handlers["web_search"] = webSearchHost.ExecuteAsync;
        }
        if (responsePresenter is not null)
        {
            var respondHost = new BuiltinAgentRespondToolHost(responsePresenter, clipboard);
            handlers["respond"] = respondHost.ExecuteAsync;
        }
        if (questionPresenter is not null)
        {
            var questionHost = new BuiltinAgentAskUserQuestionToolHost(questionPresenter);
            handlers["ask_user_question"] = questionHost.ExecuteAsync;
        }
        var dispatcher = new BuiltinAgentToolDispatcher(handlers);

        return ExecuteAsync(
            taskId,
            voiceInstruction,
            context,
            workspaceDirectory,
            onEvent,
            dispatcher.DispatchAsync,
            cancellationToken);
    }
}
