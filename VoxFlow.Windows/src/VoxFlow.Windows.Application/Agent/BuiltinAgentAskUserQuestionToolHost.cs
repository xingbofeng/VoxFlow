using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentQuestionOption(string Label, string Description, string? Preview);
public sealed record AgentQuestion(string Question, string Header, IReadOnlyList<AgentQuestionOption> Options, bool MultiSelect);
public interface IAgentQuestionPresenter { Task<IReadOnlyDictionary<string, IReadOnlyList<string>>?> AskAsync(IReadOnlyList<AgentQuestion> questions, CancellationToken cancellationToken); }

public sealed class BuiltinAgentAskUserQuestionToolHost
{
    private readonly IAgentQuestionPresenter presenter;
    public BuiltinAgentAskUserQuestionToolHost(IAgentQuestionPresenter presenter) => this.presenter = presenter ?? throw new ArgumentNullException(nameof(presenter));
    public async Task<AgentToolResult> ExecuteAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        if (call.Arguments.TryGetProperty("answers", out _)) return AgentToolResult.Failure(call.Name, "model_answers_not_allowed");
        if (!call.Arguments.TryGetProperty("questions", out var raw) || raw.ValueKind != JsonValueKind.Array) return AgentToolResult.Failure(call.Name, "missing_questions");
        var values = raw.EnumerateArray().ToArray();
        if (values.Length is < 1 or > 4) return AgentToolResult.Failure(call.Name, "invalid_question_count");
        var questions = new List<AgentQuestion>(values.Length);
        foreach (var value in values) { var question = ParseQuestion(value); if (question.Error is { } error) return AgentToolResult.Failure(call.Name, error); questions.Add(question.Value!); }
        if (questions.Select(q => q.Question).Distinct(StringComparer.Ordinal).Count() != questions.Count) return AgentToolResult.Failure(call.Name, "duplicate_question");
        var answers = await presenter.AskAsync(questions, cancellationToken).ConfigureAwait(false);
        if (answers is null) return AgentToolResult.Failure(call.Name, "question_cancelled");
        if (!AnswersAreValid(questions, answers)) return AgentToolResult.Failure(call.Name, "invalid_user_answers");
        var serializedAnswers = answers.ToDictionary(pair => pair.Key, pair => pair.Value.Count == 1 ? (object)pair.Value[0] : pair.Value.ToArray());
        return AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { kind = "questions_answered", questions, answers = serializedAnswers }));
    }
    private static (AgentQuestion? Value, string? Error) ParseQuestion(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) return (null, "invalid_question");
        if (!String(value, "question", out var text)) return (null, "missing_question_text");
        if (!String(value, "header", out var header)) return (null, "missing_question_header");
        if (header.Length > 12) return (null, "question_header_too_long");
        if (!value.TryGetProperty("options", out var rawOptions) || rawOptions.ValueKind != JsonValueKind.Array) return (null, "missing_question_options");
        var options = rawOptions.EnumerateArray().ToArray(); if (options.Length is < 1 or > 4) return (null, "invalid_option_count");
        var parsed = new List<AgentQuestionOption>();
        foreach (var option in options) { if (option.ValueKind != JsonValueKind.Object || !String(option, "label", out var label)) return (null, "missing_option_label"); if (!String(option, "description", out var description)) return (null, "missing_option_description"); _ = String(option, "preview", out var preview); parsed.Add(new(label, description, preview)); }
        if (parsed.Select(p => p.Label).Distinct(StringComparer.Ordinal).Count() != parsed.Count) return (null, "duplicate_option_label");
        var multi = value.TryGetProperty("multiSelect", out var multiValue) && multiValue.ValueKind == JsonValueKind.True;
        return (new(text, header, parsed, multi), null);
    }
    private static bool AnswersAreValid(IReadOnlyList<AgentQuestion> questions, IReadOnlyDictionary<string, IReadOnlyList<string>> answers) => questions.All(question => answers.TryGetValue(question.Question, out var selected) && selected.Count > 0 && (question.MultiSelect || selected.Count == 1) && selected.All(label => question.Options.Any(option => option.Label == label)));
    private static bool String(JsonElement value, string name, out string text) { text = string.Empty; return value.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(text = item.GetString() ?? string.Empty); }
}
