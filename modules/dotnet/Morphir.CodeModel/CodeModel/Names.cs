using Morphir.CodeModel.Common;
using Vogen;

namespace Morphir.CodeModel;

[ValueObject<string>]
public partial struct CanonicalName
{
    internal static string NormalizeInput(string input)
    {
        var parts = Common.CanonicalName
            .WordPattern()
            .Matches(input).Select(m => m.Value.ToLowerInvariant());
        return string.Join("-", parts);
    }
}