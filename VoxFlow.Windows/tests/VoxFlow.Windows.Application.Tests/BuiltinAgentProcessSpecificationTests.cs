using System.Security.Cryptography;
using System.Text;
using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentProcessSpecificationTests
{
    [Fact]
    public void Absolute_verified_binary_uses_stdio_and_never_puts_secret_in_arguments_or_environment()
    {
        var temporary = Path.GetTempFileName();
        try
        {
            File.WriteAllText(temporary, "sidecar");
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("sidecar")));
            var request = Request("super-secret");
            var specification = new BuiltinAgentProcessSpecification(
                new BuiltinAgentBinaryDescriptor(temporary, hash));

            var startInfo = specification.CreateStartInfo(request);

            Assert.Equal(Path.GetFullPath(temporary), startInfo.FileName);
            Assert.Empty(startInfo.ArgumentList);
            Assert.DoesNotContain(
                startInfo.Environment,
                entry => entry.Value?.Contains("super-secret", StringComparison.Ordinal) == true);
            Assert.True(startInfo.RedirectStandardInput);
            Assert.True(startInfo.RedirectStandardOutput);
            Assert.True(startInfo.RedirectStandardError);
        }
        finally
        {
            File.Delete(temporary);
        }
    }

    [Fact]
    public void Relative_or_tampered_binary_is_rejected_before_process_start()
    {
        Assert.Throws<ArgumentException>(() => new BuiltinAgentBinaryDescriptor("agent.exe", "AA"));

        var temporary = Path.GetTempFileName();
        try
        {
            File.WriteAllText(temporary, "actual");
            var specification = new BuiltinAgentProcessSpecification(
                new BuiltinAgentBinaryDescriptor(temporary, new string('0', 64)));

            Assert.Throws<InvalidOperationException>(() => specification.CreateStartInfo(Request("secret")));
        }
        finally
        {
            File.Delete(temporary);
        }
    }

    private static BuiltinAgentSidecarRunRequest Request(string secret) => new(
        "task-1", "instruction",
        new BuiltinAgentSidecarProviderConfig("provider", "https://example.test", "model", secret, 30),
        [new BuiltinAgentSidecarContentPart("intent")],
        new BuiltinAgentSidecarLoopLimits());
}
