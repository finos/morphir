using System.Text.RegularExpressions;

namespace Morphir.CodeModel.Common;

internal static partial class Naming
{
    [GeneratedRegex("([a-zA-Z][a-z]*|[0-9]+)")]
    private static partial Regex WordPattern();

    public static IEnumerable<string> ToCanonicalizedSegments(this string input)
    {
        return WordPattern().Matches(input).Select(m => m.Value.ToLowerInvariant());
    }

    public static ReadOnlySpan<string> ToCanonicalizedSpan(this string input)
    {
        return ToCanonicalizedSegments(input).ToArray();
    }
}