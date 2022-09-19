module Morphir.Scala.Feature.CoreTests exposing (..)

import Expect
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Path as IRPath
import Morphir.IR.Type as IRType
import Morphir.Scala.AST as Scala
import Morphir.Scala.Feature.Core as Core
import Test exposing (Test, describe, test)


mapValueNameTests : Test
mapValueNameTests =
    let
        assert inList outString =
            test ("Genarated Scala name " ++ outString) <|
                \_ ->
                    Name.fromList inList
                        |> Core.mapValueName
                        |> Expect.equal outString
    in
    describe "toScalaName"
        [ assert [ "full", "name" ] "fullName"
        , assert [ "implicit" ] "_implicit"
        ]


mapFQNameToPathAndNameTests : Test
mapFQNameToPathAndNameTests =
    let
        assert inFQName outTuple =
            test ("Generate Path and Name " ++ FQName.toString inFQName) <|
                \_ ->
                    inFQName
                        |> Core.mapFQNameToPathAndName
                        |> Expect.equal outTuple
    in
    describe "toPathAndName"
        [ assert (FQName.fQName (IRPath.fromList [ Name.fromList [ "Morphir" ], Name.fromList [ "Reference" ], Name.fromList [ "Model" ] ]) (IRPath.fromList [ Name.fromList [ "Insight" ] ]) (Name.fromList [ "UseCase1" ]))
            ( [ "morphir", "reference", "model", "Insight" ], [ "UseCase1" ] )
        , assert (FQName.fQName (IRPath.fromList [ Name.fromList [ "alpha" ], Name.fromList [ "beta" ], Name.fromList [ "gamma" ] ]) (IRPath.fromList [ Name.fromList [ "omega" ] ]) (Name.fromList [ "phi" ]))
            ( [ "alpha", "beta", "gamma", "Omega" ], [ "phi" ] )
        ]


mapFQNameToTypeRefTests : Test
mapFQNameToTypeRefTests =
    let
        assert inFQName outTypeRef =
            test "Generated Type Reference" <|
                \_ ->
                    inFQName
                        |> Core.mapFQNameToTypeRef
                        |> Expect.equal outTypeRef
    in
    describe "toTypeRef"
        [ assert (FQName.fQName (IRPath.fromList [ Name.fromList [ "Morphir" ], Name.fromList [ "Reference" ], Name.fromList [ "Model" ] ]) (IRPath.fromList [ Name.fromList [ "Insight" ] ]) (Name.fromList [ "UseCase1" ]))
            (Scala.TypeRef [ "morphir", "reference", "model", "Insight" ] "UseCase1")
        ]


mapTypeTests_Variable : Test
mapTypeTests_Variable =
    let
        scalaVariableType =
            Core.mapType (IRType.Variable () [ "foo" ])
    in
    describe "Map Morphir IR Variable to Scala Type Variable"
        [ test "Map IR String to Scala String" <|
            \_ ->
                scalaVariableType |> Expect.equal (Scala.TypeVar "Foo")
        ]


mapTypeTests_Reference : Test
mapTypeTests_Reference =
    describe "Map IR Reference to Scala Reference"
        [ test "Map IR String to Scala String" <|
            \_ ->
                Core.mapType (IRType.Reference () (FQName.fqn "Morphir.sdk" "string" "string") [])
                    |> Expect.equal (Scala.TypeRef [ "morphir", "sdk", "String" ] "String")
        , test "Map IR List String to Scala List String" <|
            \_ ->
                let
                    type1 =
                        IRType.Reference () (FQName.fqn "Morphir.sdk" "string" "string")
                in
                Core.mapType (IRType.Reference () (FQName.fqn "Morphir.sdk" "string" "string") [])
                    |> Expect.equal (Scala.TypeRef [ "morphir", "sdk", "String" ] "String")
        ]


mapTypeTest_Tuple : Test
mapTypeTest_Tuple =
    let
        assert inIRTuple outScalaTuple =
            test "Generated Tuple Variable" <|
                \_ ->
                    inIRTuple
                        |> Core.mapType
                        |> Expect.equal outScalaTuple
    in
    describe "Map Morphir IR Tuple type to Scala Tuple"
        [ assert (IRType.Tuple () [ IRType.Variable () [ "foo" ] ])
            (Scala.TupleType [ Scala.TypeVar "Foo" ])
        ]


mapTypeTests_Record : Test
mapTypeTests_Record =
    let
        field1 : IRType.Field ()
        field1 =
            IRType.Field [ "foo" ] (IRType.Reference () (FQName.fromString "Morphir.SDK.Basics.String" ".") [])

        field2 : IRType.Field ()
        field2 =
            IRType.Field [ "bar" ] (IRType.Reference () (FQName.fqn "Morphir.sdk" "Basics" "string") [])

        scalafield1 : Scala.MemberDecl
        scalafield1 =
            Scala.FunctionDecl
                { modifiers = []
                , name = Core.mapValueName [ "bar" ]
                , typeArgs = []
                , args = []
                , returnType = Just (Core.mapType (IRType.Reference () (FQName.fqn "Morphir.SDK" "Basics" "String") []))
                , body = Nothing
                }
    in
    describe "Record Mapping Test"
        [ test "Test for record with empty field" <|
            \_ -> Core.mapType (IRType.Record () []) |> Expect.equal (Scala.StructuralType [])
        , test "Test for record with a single field" <|
            \_ -> Core.mapType (IRType.Record () [ field2 ]) |> Expect.equal (Scala.StructuralType [ scalafield1 ])
        ]


mapTypeTests_ExtensibleRecord : Test
mapTypeTests_ExtensibleRecord =
    let
        iRField1 : IRType.Field ()
        iRField1 =
            IRType.Field [ "foo" ] (IRType.Reference () (FQName.fqn "Morphir" "sdk" "String") [])

        scalafield1 : Scala.MemberDecl
        scalafield1 =
            Scala.FunctionDecl
                { modifiers = []
                , name = Core.mapValueName [ "foo" ]
                , typeArgs = []
                , args = []
                , returnType = Just (Core.mapType (IRType.Reference () (FQName.fromString "Morphir.SDK.Basics.String" ".") []))
                , body = Nothing
                }
    in
    describe "Extensible Record Mapping"
        [ test "Test for empty extensible record" <|
            \_ -> Core.mapType (IRType.ExtensibleRecord () [ "foo" ] []) |> Expect.equal (Scala.StructuralType [])
        , test "Test for extensible record with single field" <|
            \_ -> Core.mapType (IRType.ExtensibleRecord () [ "bar" ] [ iRField1 ]) |> Expect.notEqual (Scala.StructuralType [ scalafield1 ])
        ]



-- Map Function types


matTypeTests_Function : Test
matTypeTests_Function =
    describe "Map function test"
        [ test "Test for function of string and string" <|
            \_ ->
                Core.mapType (IRType.Function () (IRType.Reference () (FQName.fqn "Morphir.sdk" "Basics" "String") []) (IRType.Reference () (FQName.fqn "Morphir.SDK" "Basics" "String") []))
                    |> Expect.equal (Scala.FunctionType (Scala.TypeRef [ "morphir", "sdk", "Basics" ] "String") (Scala.TypeRef [ "morphir", "sdk", "Basics" ] "String"))
        ]
