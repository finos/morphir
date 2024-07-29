using System.Text.RegularExpressions;

namespace Morphir.CodeModel.Common;

internal static partial class CanonicalName
{
    [GeneratedRegex("([a-zA-Z][a-z]*|[0-9]+)")]
    internal static partial Regex WordPattern();
}