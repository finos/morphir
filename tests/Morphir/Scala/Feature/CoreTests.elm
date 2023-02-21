module Morphir.Scala.Feature.CoreTests exposing (..)

import Expect
import Morphir.IR.AccessControlled as Access
import Morphir.IR.FQName as FQName
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as IRPath
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as IRType
import Morphir.IR.Value as IRValue
import Morphir.Scala.AST as Scala
import Morphir.Scala.Common as Core
import Morphir.Scala.Feature.Core as Core
import Set exposing (Set)
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


testConstructorTypeAscription : Test
testConstructorTypeAscription =
    let
        packageName =
            "package"

        moduleName =
            "Module"

        defaultScalaRef name =
            Scala.Ref [ packageName, moduleName ] name

        morphirFQN name =
            ( [ [ packageName ] ], [ [ moduleName ] ], [ name ] )

        customTypeFQN =
            morphirFQN "Custom"

        assert : String -> IRValue.Value ta (IRType.Type ()) -> Scala.Value -> Test
        assert name value expectedScalaOutput =
            test name <|
                \_ ->
                    Core.mapValue Set.empty value
                        |> Expect.equal expectedScalaOutput

        expectedNoArgsCtor =
            Scala.Apply (defaultScalaRef "target1")
                [ Scala.ArgValue Nothing
                    (Scala.TypeAscripted (defaultScalaRef "ZeroArgCtor") (Scala.TypeRef [ packageName, moduleName ] "Custom"))
                ]

        expectedOneArgCtor : Scala.Value
        expectedOneArgCtor =
            Scala.Apply (defaultScalaRef "target1")
                [ Scala.ArgValue Nothing
                    (Scala.TypeAscripted
                        (Scala.Apply (defaultScalaRef "OneArgCtor")
                            [ Scala.ArgValue Nothing (Scala.Variable "str")
                            ]
                        )
                        (Scala.TypeRef [ packageName, moduleName ] "Custom")
                    )
                ]

        expectedTwoArgCtor : Scala.Value
        expectedTwoArgCtor =
            Scala.Apply
                (Scala.Apply (defaultScalaRef "target2")
                    [ Scala.ArgValue Nothing
                        (Scala.TypeAscripted
                            (Scala.Apply (defaultScalaRef "OneArgCtor")
                                [ Scala.ArgValue Nothing (Scala.Variable "str")
                                ]
                            )
                            (Scala.TypeRef [ packageName, moduleName ] "Custom")
                        )
                    ]
                )
                [ Scala.ArgValue Nothing
                    (Scala.TypeAscripted
                        (Scala.Apply (defaultScalaRef "TwoArgCtor")
                            [ Scala.ArgValue Nothing (Scala.Variable "str")
                            , Scala.ArgValue Nothing (Scala.Variable "int")
                            ]
                        )
                        (Scala.TypeRef [ packageName, moduleName ] "Custom")
                    )
                ]

        expectedPartialApplyCtor : Scala.Value
        expectedPartialApplyCtor =
            Scala.Apply
                (defaultScalaRef "target3")
                [ Scala.ArgValue Nothing
                    (Scala.TypeAscripted (defaultScalaRef "TwoArgCtor")
                        (Scala.FunctionType
                            (Scala.FunctionType
                                (Scala.TypeRef [ "morphir", "sdk", "String" ] "String")
                                (Scala.TypeRef [ "morphir", "sdk", "Basics" ] "Int")
                            )
                            (Scala.TypeRef [ packageName, moduleName ] "Custom")
                        )
                    )
                ]

        noArgFun : IRValue.Value ta (IRType.Type ())
        noArgFun =
            IRValue.Apply (IRType.Unit ())
                (IRValue.Reference
                    (IRType.Function ()
                        (IRType.Reference () (morphirFQN "custom") [])
                        (IRType.Unit ())
                    )
                    (morphirFQN "target1")
                )
                (IRValue.Constructor (IRType.Reference () (morphirFQN "custom") []) (morphirFQN "ZeroArgCtor"))

        oneArgFun : IRValue.Value ta (IRType.Type ())
        oneArgFun =
            IRValue.Apply (boolType ())
                (IRValue.Reference
                    (IRType.Function ()
                        (IRType.Reference ()
                            customTypeFQN
                            []
                        )
                        (boolType ())
                    )
                    (morphirFQN "target1")
                )
                (IRValue.Apply (IRType.Reference () customTypeFQN [])
                    (IRValue.Constructor
                        (IRType.Function ()
                            (stringType ())
                            (IRType.Reference () customTypeFQN [])
                        )
                        (morphirFQN "OneArgCtor")
                    )
                    (IRValue.Variable (stringType ()) [ "str" ])
                )

        twoCustomArgsFun : IRValue.Value ta (IRType.Type ())
        twoCustomArgsFun =
            IRValue.Apply (boolType ())
                (IRValue.Apply (IRType.Function () (IRType.Reference () customTypeFQN []) (boolType ()))
                    (IRValue.Reference (IRType.Function () (IRType.Reference () customTypeFQN []) (boolType ()))
                        (morphirFQN "target2")
                    )
                    (IRValue.Apply (IRType.Reference () customTypeFQN [])
                        (IRValue.Constructor (IRType.Function () (stringType ()) (IRType.Reference () customTypeFQN [])) (morphirFQN "OneArgCtor"))
                        (IRValue.Variable (stringType ()) [ "str" ])
                    )
                )
                (IRValue.Apply (IRType.Reference () customTypeFQN [])
                    (IRValue.Apply (IRType.Function () (intType ()) (IRType.Reference () customTypeFQN []))
                        (IRValue.Constructor (IRType.Function () (intType ()) (IRType.Reference () customTypeFQN [])) (morphirFQN "TwoArgCtor"))
                        (IRValue.Variable (stringType ()) [ "str" ])
                    )
                    (IRValue.Variable (intType ()) [ "int" ])
                )

        partialApplyFun =
            IRValue.Apply (boolType ())
                (IRValue.Reference
                    (IRType.Function ()
                        (IRType.Function ()
                            (IRType.Function () (stringType ()) (intType ()))
                            (IRType.Reference () customTypeFQN [])
                        )
                        (boolType ())
                    )
                    (morphirFQN "target3")
                )
                (IRValue.Constructor
                    (IRType.Function ()
                        (IRType.Function () (stringType ()) (intType ()))
                        (IRType.Reference () customTypeFQN [])
                    )
                    (morphirFQN "TwoArgCtor")
                )
    in
    describe "Type ascribe constructors values"
        [ assert "Generated Scala Constructors Are Type... " noArgFun expectedNoArgsCtor
        , assert "Generated Scala For OneArgs Ctor TypeAscription ... " oneArgFun expectedOneArgCtor
        , assert "Generated Scala For TwoArgs Ctor TypeAscription ... " twoCustomArgsFun expectedTwoArgCtor
        , assert "Generated Scala For Partially Applied" partialApplyFun expectedPartialApplyCtor
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


mapPrivateMemberTests : Test
mapPrivateMemberTests =
    describe "Map private member test"
        [ test "private modules should become public" <|
            \_ ->
                Core.mapModuleDefinition [ [ "foo" ] ]
                    [ [ "bar" ] ]
                    (Access.private
                        Module.emptyDefinition
                    )
                    |> Expect.equal
                        [ Scala.CompilationUnit [ "foo" ]
                            "Bar.scala"
                            [ "foo" ]
                            []
                            [ { doc = Just "Generated based on Bar"
                              , value =
                                    { annotations = []
                                    , value =
                                        Scala.Object
                                            { modifiers = []
                                            , name = "Bar"
                                            , body = Nothing
                                            , members = []
                                            , extends = []
                                            }
                                    }
                              }
                            ]
                        ]
        ]
