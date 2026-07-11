using System.Text.Json;
using System.Text.Json.Serialization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class DomainSerializationTests
{
    [Fact]
    public void Provider_and_Qwen_variant_use_stable_wire_identifiers()
    {
        var selection = new AsrSelection(AsrProviderId.Qwen, QwenVariant.Qwen06B);

        var json = JsonSerializer.Serialize(selection, DomainJson.Options);
        using var document = JsonDocument.Parse(json);

        Assert.Equal("qwen3_asr", document.RootElement.GetProperty("provider").GetString());
        Assert.Equal("0.6b", document.RootElement.GetProperty("qwenVariant").GetString());
        Assert.Equal(
            selection,
            JsonSerializer.Deserialize<AsrSelection>(json, DomainJson.Options));
    }

    [Theory]
    [InlineData(AsrProviderId.TencentCloud, "tencent_cloud_asr")]
    [InlineData(AsrProviderId.AliyunDashScope, "aliyun_dashscope_asr")]
    [InlineData(AsrProviderId.Volcengine, "volcengine_doubao_asr")]
    public void Cloud_provider_wire_identifiers_round_trip(
        AsrProviderId provider,
        string wireIdentifier)
    {
        var selection = new AsrSelection(provider, null);

        var json = JsonSerializer.Serialize(selection, DomainJson.Options);
        using var document = JsonDocument.Parse(json);

        Assert.Equal(wireIdentifier, document.RootElement.GetProperty("provider").GetString());
        Assert.Equal(
            selection,
            JsonSerializer.Deserialize<AsrSelection>(json, DomainJson.Options));
    }

    [Theory]
    [InlineData("{\"provider\":999,\"qwenVariant\":null}")]
    [InlineData("{\"provider\":\"unknown\",\"qwenVariant\":null}")]
    public void Unknown_or_numeric_enum_wire_values_are_rejected(string json)
    {
        Assert.Throws<JsonException>(() =>
            JsonSerializer.Deserialize<AsrSelection>(json, DomainJson.Options));
    }

    [Theory]
    [MemberData(nameof(MissingRequiredConstructorParameterCases))]
    public void Missing_required_constructor_parameters_are_rejected(
        Type type,
        string json)
    {
        Assert.Throws<JsonException>(() =>
            JsonSerializer.Deserialize(json, type, DomainJson.Options));
    }

    public static TheoryData<Type, string> MissingRequiredConstructorParameterCases => new()
    {
        { typeof(AsrSelection), "{\"qwenVariant\":\"0.6b\"}" },
        { typeof(LlmState), "{\"model\":null,\"errorCode\":null}" },
        { typeof(OutputResult), "{\"errorCode\":null}" },
        { typeof(HistoryRetentionPolicy), "{\"days\":null}" },
        { typeof(WindowBounds), "{\"top\":0,\"width\":640,\"height\":480}" },
        {
            typeof(UiState),
            "{\"monitorId\":null,\"mainWindowBounds\":null}"
        },
        { typeof(VoxFlowError), "{\"provider\":null}" },
        { typeof(VoxFlowErrorClassification), "{\"isRetryable\":false}" },
    };

    [Fact]
    public void Persisted_enum_wire_names_are_explicit_and_stable()
    {
        var goldenValues = new (Enum Value, string WireName)[]
        {
            (ModelInstallPhase.NotDownloaded, "notDownloaded"),
            (ModelInstallPhase.Queued, "queued"),
            (ModelInstallPhase.Downloading, "downloading"),
            (ModelInstallPhase.Paused, "paused"),
            (ModelInstallPhase.Verifying, "verifying"),
            (ModelInstallPhase.Installing, "installing"),
            (ModelInstallPhase.Prewarming, "prewarming"),
            (ModelInstallPhase.CanaryTesting, "canaryTesting"),
            (ModelInstallPhase.Ready, "ready"),
            (ModelInstallPhase.Deleting, "deleting"),
            (ModelInstallPhase.InsufficientSpace, "insufficientSpace"),
            (ModelInstallPhase.Corrupted, "corrupted"),
            (ModelInstallPhase.RuntimeUnsupported, "runtimeUnsupported"),
            (ModelInstallPhase.HardwareUnsupported, "hardwareUnsupported"),
            (ModelInstallPhase.Failed, "failed"),
            (LlmAvailability.NotConfigured, "notConfigured"),
            (LlmAvailability.Disabled, "disabled"),
            (LlmAvailability.Testing, "testing"),
            (LlmAvailability.Ready, "ready"),
            (LlmAvailability.Failed, "failed"),
            (OutputResultKind.Inserted, "inserted"),
            (OutputResultKind.Copied, "copied"),
            (OutputResultKind.TargetChanged, "targetChanged"),
            (OutputResultKind.PermissionDenied, "permissionDenied"),
            (OutputResultKind.InjectionFailed, "injectionFailed"),
            (OutputResultKind.CopyFailed, "copyFailed"),
            (OutputResultKind.Cancelled, "cancelled"),
            (HistoryRetentionMode.Disabled, "disabled"),
            (HistoryRetentionMode.RetainForDays, "retainForDays"),
            (HistoryRetentionMode.Forever, "forever"),
            (VoxFlowErrorCode.AsrNotConfigured, "asrNotConfigured"),
            (VoxFlowErrorCode.MicrophonePermissionDenied, "microphonePermissionDenied"),
            (VoxFlowErrorCode.AudioDeviceUnavailable, "audioDeviceUnavailable"),
            (VoxFlowErrorCode.AudioFormatInvalid, "audioFormatInvalid"),
            (VoxFlowErrorCode.NetworkFailure, "networkFailure"),
            (VoxFlowErrorCode.AuthenticationFailed, "authenticationFailed"),
            (VoxFlowErrorCode.QuotaExceeded, "quotaExceeded"),
            (VoxFlowErrorCode.ProviderFailure, "providerFailure"),
            (VoxFlowErrorCode.FinalTimeout, "finalTimeout"),
            (VoxFlowErrorCode.EmptyFinal, "emptyFinal"),
            (VoxFlowErrorCode.ModelNotReady, "modelNotReady"),
            (VoxFlowErrorCode.NativeRuntimeFailure, "nativeRuntimeFailure"),
            (VoxFlowErrorCode.TargetChanged, "targetChanged"),
            (VoxFlowErrorCode.ClipboardFailure, "clipboardFailure"),
            (VoxFlowErrorCode.InputPermissionDenied, "inputPermissionDenied"),
            (VoxFlowErrorCode.InputInjectionFailure, "inputInjectionFailure"),
            (VoxFlowErrorCode.Unknown, "unknown"),
            (VoxFlowErrorCategory.Configuration, "configuration"),
            (VoxFlowErrorCategory.Permission, "permission"),
            (VoxFlowErrorCategory.Audio, "audio"),
            (VoxFlowErrorCategory.Network, "network"),
            (VoxFlowErrorCategory.Provider, "provider"),
            (VoxFlowErrorCategory.Model, "model"),
            (VoxFlowErrorCategory.Output, "output"),
            (VoxFlowErrorCategory.System, "system"),
        };
        var nonPersistenceNamingPolicy = new JsonSerializerOptions();
        nonPersistenceNamingPolicy.Converters.Add(
            new JsonStringEnumConverter(
                JsonNamingPolicy.SnakeCaseUpper,
                allowIntegerValues: false));

        foreach (var (value, wireName) in goldenValues)
        {
            var expectedJson = $"\"{wireName}\"";

            Assert.Equal(
                expectedJson,
                JsonSerializer.Serialize(value, value.GetType(), DomainJson.Options));
            Assert.Equal(
                expectedJson,
                JsonSerializer.Serialize(value, value.GetType(), nonPersistenceNamingPolicy));
        }
    }

    [Fact]
    public void Immutable_domain_values_round_trip_without_sensitive_free_text()
    {
        var snapshot = new DomainSerializationFixture(
            new LlmState(
                LlmAvailability.Failed,
                "hunyuan-lite",
                VoxFlowErrorCode.AuthenticationFailed),
            new OutputResult(
                OutputResultKind.TargetChanged,
                VoxFlowErrorCode.TargetChanged),
            HistoryRetentionPolicy.Default,
            new UiState(
                "monitor-1",
                new WindowBounds(20, 30, 1260, 720),
                false),
            ModelInstallPhase.Prewarming,
            new VoxFlowError(
                VoxFlowErrorCode.ProviderFailure,
                AsrProviderId.TencentCloud));

        var json = JsonSerializer.Serialize(snapshot, DomainJson.Options);
        var restored = JsonSerializer.Deserialize<DomainSerializationFixture>(
            json,
            DomainJson.Options);

        Assert.Equal(snapshot, restored);
        Assert.DoesNotContain("message", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("credential", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("secret", json, StringComparison.OrdinalIgnoreCase);
    }

    private sealed record DomainSerializationFixture(
        LlmState Llm,
        OutputResult Output,
        HistoryRetentionPolicy History,
        UiState Ui,
        ModelInstallPhase ModelPhase,
        VoxFlowError Error);
}
