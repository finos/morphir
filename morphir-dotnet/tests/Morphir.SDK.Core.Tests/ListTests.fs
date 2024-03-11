module Morphir.SDK.ListTests

open Morphir.SDK.Testing
open Morphir.SDK

[<Tests>]
let tests =
    let mapTests = describe "List.map" []

    describe "ListTests" [ mapTests ]
