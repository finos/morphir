using FluentAssertions;
using Xunit;

namespace Morphir.CodeModel;

public class CanonicalNameTests
{
    // [Fact(DisplayName = "Test")]
    // public Task CanonicalNameCreation()
    // {
    //     return Given(() => "Morphir.IR.Name")
    //         .When(data => CanonicalName.From(data))
    //         .Then(result =>
    //             result.Value == "morphir-i-r-name"
    //         );
    // }

    [Theory]
    [InlineData("fooBar_baz 123", "foo-bar-baz-123")]
    [InlineData("valueInUSD", "value-in-u-s-d")]
    [InlineData("ValueInUSD", "value-in-u-s-d")]
    [InlineData("value_in_USD", "value-in-u-s-d")]
    public void CanonicalName_Should_Be_Creatable_From_A_Valid_String(string input, string expected)
    {
        var actual = CanonicalName.From(input);
        actual.Value.Should().Be(expected);
    }
}