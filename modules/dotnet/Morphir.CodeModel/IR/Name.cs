using System.Buffers;

namespace Morphir.IR;

public record class Name(ReadOnlySequence<string> Segments)
{
    public static Name FromString(string input)
    {
        throw new NotImplementedException("TODO");
    }
}