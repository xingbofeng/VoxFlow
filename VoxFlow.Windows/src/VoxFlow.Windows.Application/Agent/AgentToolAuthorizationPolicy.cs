using System.Text.RegularExpressions;

namespace VoxFlow.Windows.Application.Agent;

/// <summary>
/// Host-side guard for tools that expose retained user data. The sidecar can
/// propose calls, but only the trusted voice instruction can authorize local
/// transcription search; untrusted desktop context is never considered.
/// </summary>
public sealed class AgentToolAuthorizationPolicy
{
    private static readonly Regex TranscriptionReference = new(
        @"(?ix)(?:
            \b(?:transcription|transcript|dictation|voice\s*(?:history|record|note)|history)\b
            | 转写 | 听写 | 语音\s*(?:历史|记录|内容)? | 历史(?:记录)? | 之前(?:说过|录过)? | 上次(?:说过|录过)?
        )",
        RegexOptions.CultureInvariant,
        TimeSpan.FromMilliseconds(100));
    private static readonly Regex OpenVerb = new(
        @"(?ix)\b(?:open|visit|browse|navigate(?:\s+to)?)\b|打开|访问|跳转(?:到)?",
        RegexOptions.CultureInvariant,
        TimeSpan.FromMilliseconds(100));
    private readonly string trustedVoiceInstruction;
    private static readonly IReadOnlySet<string> PreapprovedWebFetchHosts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "developer.apple.com", "docs.swift.org", "doc.rust-lang.org", "docs.python.org",
        "developer.mozilla.org", "github.com", "modelcontextprotocol.io", "platform.claude.com",
        "react.dev", "go.dev", "pkg.go.dev",
    };

    public AgentToolAuthorizationPolicy(string trustedVoiceInstruction)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(trustedVoiceInstruction);
        this.trustedVoiceInstruction = trustedVoiceInstruction;
    }

    public bool AllowsTranscriptionSearch() =>
        TranscriptionReference.IsMatch(trustedVoiceInstruction);

    public bool AllowsOpenUrl(Uri uri)
    {
        ArgumentNullException.ThrowIfNull(uri);
        if (uri.Scheme is not ("http" or "https") || !uri.IsAbsoluteUri)
        {
            return false;
        }
        return OpenVerb.IsMatch(trustedVoiceInstruction)
            && (trustedVoiceInstruction.Contains(uri.OriginalString, StringComparison.OrdinalIgnoreCase)
                || trustedVoiceInstruction.Contains(uri.AbsoluteUri, StringComparison.OrdinalIgnoreCase));
    }

    public bool AllowsHttpRequest(Uri uri)
    {
        ArgumentNullException.ThrowIfNull(uri);
        return uri.Scheme == Uri.UriSchemeHttps
            && uri.IsAbsoluteUri
            && (trustedVoiceInstruction.Contains(uri.OriginalString, StringComparison.OrdinalIgnoreCase)
                || trustedVoiceInstruction.Contains(uri.AbsoluteUri, StringComparison.OrdinalIgnoreCase));
    }

    public bool AllowsWebFetch(Uri uri)
    {
        ArgumentNullException.ThrowIfNull(uri);
        return uri.IsAbsoluteUri
            && uri.Scheme is "http" or "https"
            && string.IsNullOrEmpty(uri.UserInfo)
            && (trustedVoiceInstruction.Contains(uri.AbsoluteUri, StringComparison.OrdinalIgnoreCase)
                || PreapprovedWebFetchHosts.Contains(uri.Host));
    }
}
