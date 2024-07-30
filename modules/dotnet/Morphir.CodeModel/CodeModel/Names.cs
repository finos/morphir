using Morphir.CodeModel.Common;
using Vogen;

namespace Morphir.CodeModel;

[ValueObject<string>]
public partial struct CanonicalName
{
    internal static string NormalizeInput(string input)
    {
        return string.Join("-", input.ToCanonicalizedSegments());
    }
}