using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentAskUserQuestionToolHostTests
{
    [Fact]
    public async Task Presents_questions_and_returns_real_presenter_answers()
    {
        var presenter = new FakePresenter(new[] { "Native" });
        var result = await new BuiltinAgentAskUserQuestionToolHost(presenter).ExecuteAsync(Call(new { questions = new[] { Question() } }), CancellationToken.None);
        Assert.True(result.Ok); Assert.Single(presenter.Questions!);
        Assert.Equal("Native", result.Result!.Value.GetProperty("answers").GetProperty("Choose implementation").GetString());
    }
    [Theory]
    [InlineData(0)] [InlineData(5)]
    public async Task Enforces_one_to_four_questions(int count)
    {
        var result = await new BuiltinAgentAskUserQuestionToolHost(new FakePresenter([])).ExecuteAsync(Call(new { questions = Enumerable.Range(0, count).Select(_ => Question()).ToArray() }), CancellationToken.None);
        Assert.Equal("invalid_question_count", result.Error?.Code);
    }
    [Fact]
    public async Task Rejects_model_supplied_answers_and_invalid_headers()
    {
        var answers = await new BuiltinAgentAskUserQuestionToolHost(new FakePresenter([])).ExecuteAsync(Call(new { questions = new[] { Question() }, answers = new { x = "bad" } }), CancellationToken.None);
        var header = await new BuiltinAgentAskUserQuestionToolHost(new FakePresenter([])).ExecuteAsync(Call(new { questions = new[] { new { question = "Q", header = "header-too-long", options = new[] { new { label = "a", description = "a" } } } } }), CancellationToken.None);
        Assert.Equal("model_answers_not_allowed", answers.Error?.Code); Assert.Equal("question_header_too_long", header.Error?.Code);
    }
    [Fact]
    public async Task Cancel_and_invalid_presenter_answers_do_not_succeed()
    {
        var cancel = await new BuiltinAgentAskUserQuestionToolHost(new CancelPresenter()).ExecuteAsync(Call(new { questions = new[] { Question() } }), CancellationToken.None);
        var invalid = await new BuiltinAgentAskUserQuestionToolHost(new FakePresenter(new[] { "unknown" })).ExecuteAsync(Call(new { questions = new[] { Question() } }), CancellationToken.None);
        Assert.Equal("question_cancelled", cancel.Error?.Code); Assert.Equal("invalid_user_answers", invalid.Error?.Code);
    }
    private static object Question() => new { question = "Choose implementation", header = "Approach", options = new[] { new { label = "Native", description = "Use native." }, new { label = "Sidecar", description = "Use helper." } }, multiSelect = false };
    private static AgentToolCall Call(object args) => new("ask-1", "ask_user_question", JsonSerializer.SerializeToElement(args));
    private sealed class FakePresenter(IReadOnlyList<string> selected) : IAgentQuestionPresenter { public IReadOnlyList<AgentQuestion>? Questions { get; private set; } public Task<IReadOnlyDictionary<string, IReadOnlyList<string>>?> AskAsync(IReadOnlyList<AgentQuestion> questions, CancellationToken cancellationToken) { Questions = questions; return Task.FromResult<IReadOnlyDictionary<string, IReadOnlyList<string>>?>(new Dictionary<string, IReadOnlyList<string>> { [questions[0].Question] = selected }); } }
    private sealed class CancelPresenter : IAgentQuestionPresenter { public Task<IReadOnlyDictionary<string, IReadOnlyList<string>>?> AskAsync(IReadOnlyList<AgentQuestion> questions, CancellationToken cancellationToken) => Task.FromResult<IReadOnlyDictionary<string, IReadOnlyList<string>>?>(null); }
}
