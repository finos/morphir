module Morphir.Relational.BackendTests exposing (..)

import Expect
import Morphir.IR.SDK.List as SDKList
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue)
import Morphir.Relational.Backend as Backend
import Morphir.Relational.IR as IR exposing (Relation)
import Test exposing (Test, describe, test)


mapValueTests : Test
mapValueTests =
    let
        testRecordType1 : Type ()
        testRecordType1 =
            Type.Record () []

        positiveTest : String -> TypedValue -> Relation -> Test
        positiveTest message typedValue expectedRelation =
            test message
                (\_ ->
                    Backend.mapValue typedValue
                        |> Expect.equal (Ok expectedRelation)
                )
    in
    describe "mapValue"
        [ positiveTest "Variable to From clause"
            (Value.Variable (SDKList.listType () testRecordType1) [ "my", "relation" ])
            (IR.From [ "my", "relation" ])
        ]
