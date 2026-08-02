using System.Security.Cryptography;
using System.Text;

namespace VoxFlow.Windows.Application.Agent;

public sealed class AgentFileReadState
{
    private readonly Dictionary<string, string> hashes = new(StringComparer.OrdinalIgnoreCase);

    public void RecordFullRead(string fullPath, string content) =>
        hashes[Path.GetFullPath(fullPath)] = Hash(content);

    public bool WasReadUnchanged(string fullPath)
    {
        var normalized = Path.GetFullPath(fullPath);
        return hashes.TryGetValue(normalized, out var expected) && File.Exists(normalized)
            && string.Equals(expected, Hash(File.ReadAllText(normalized, new UTF8Encoding(false, true))), StringComparison.Ordinal);
    }

    private static string Hash(string content) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(content)));
}
