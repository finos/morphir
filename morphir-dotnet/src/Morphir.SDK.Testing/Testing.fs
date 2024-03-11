[<AutoOpen>]
module Morphir.SDK.Testing

type TestsAttribute = Expecto.TestsAttribute
let describe = Expecto.Tests.testList
let test = Expecto.Tests.test
let testCase = Expecto.Tests.testCase
let testParam = Expecto.Tests.testParam

module Expect =
    let equal expected actual =

        sprintf
            """Expected the values to be equal, but they were not:
Expected: %A
Actual  : %A
        """
            expected
            actual
        |> Expecto.Expect.equal actual expected
