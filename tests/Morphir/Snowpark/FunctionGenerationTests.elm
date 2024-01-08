module Morphir.Snowpark.FunctionGenerationTests exposing (functionGenTests)

import Dict exposing (Dict(..))
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Backend exposing (mapFunctionDefinition)
import Morphir.Snowpark.CommonTestUtils
    exposing
        ( stringTypeInstance
        , testDistributionName
        , testDistributionPackage
        )
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.Snowpark.MappingContext as MappingContext
import Set
import Test exposing (Test, describe, test)


functionGenTests : Test
functionGenTests =
    let
        customizationOptions =
            { functionsToInline = Set.empty, functionsToCache = Set.empty }

        calculatedContext =
            MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions

        typeOfRecord =
            Type.Reference () (FQName.fromString "UTest:MyMod:Emp" ":") []

        expectedFunctionBody =
            Scala.Variable "x"

        assertGenerationOfBasicFunction =
            test "Generate function definition" <|
                \_ ->
                    let
                        functionDefinition =
                            public
                                { doc = ""
                                , value =
                                    { inputTypes =
                                        [ ( Name.fromString "a", typeOfRecord, typeOfRecord )
                                        , ( Name.fromString "b", stringTypeInstance, stringTypeInstance )
                                        ]
                                    , outputType = stringTypeInstance
                                    , body = Value.Variable stringTypeInstance (Name.fromString "x")
                                    }
                                }

                        ( mappedFunctionDefinition, _ ) =
                            mapFunctionDefinition (Name.fromString "foo") functionDefinition (Path.fromString "UTest") (Path.fromString "MyMod") calculatedContext

                        expectedFunctionDeclaration =
                            Scala.FunctionDecl
                                { modifiers = []
                                , name = "foo"
                                , typeArgs = []
                                , args =
                                    [ [ Scala.ArgDecl [] (Scala.TypeRef [ "utest", "MyMod" ] "Emp") "a" Nothing ]
                                    , [ Scala.ArgDecl [] (typeRefForSnowparkType "Column") "b" Nothing ]
                                    , [ Scala.ArgDecl [ Scala.Implicit ] (typeRefForSnowparkType "Session") "sfSession" Nothing ]
                                    ]
                                , returnType = Just <| typeRefForSnowparkType "Column"
                                , body = Just expectedFunctionBody
                                }
                    in
                    Expect.equal expectedFunctionDeclaration mappedFunctionDefinition

        assertGenerationOfFunctionReturningRecord =
            test "Generate function definition returnting record" <|
                \_ ->
                    let
                        functionDefinitionReturningRec =
                            public
                                { doc = ""
                                , value =
                                    { inputTypes =
                                        [ ( Name.fromString "a", typeOfRecord, typeOfRecord )
                                        , ( Name.fromString "b", stringTypeInstance, stringTypeInstance )
                                        ]
                                    , outputType = typeOfRecord
                                    , body = Value.Variable stringTypeInstance (Name.fromString "x")
                                    }
                                }

                        ( mappedFunctionDefinitionReturningRec, _ ) =
                            mapFunctionDefinition (Name.fromString "goo") functionDefinitionReturningRec (Path.fromString "UTest") (Path.fromString "MyMod") calculatedContext

                        expectedFunctionDeclarationRec =
                            Scala.FunctionDecl
                                { modifiers = []
                                , name = "goo"
                                , typeArgs = []
                                , args =
                                    [ [ Scala.ArgDecl [] (Scala.TypeRef [ "utest", "MyMod" ] "Emp") "a" Nothing ]
                                    , [ Scala.ArgDecl [] (typeRefForSnowparkType "Column") "b" Nothing ]
                                    , [ Scala.ArgDecl [ Scala.Implicit ] (typeRefForSnowparkType "Session") "sfSession" Nothing ]
                                    ]
                                , returnType = Just <| typeRefForSnowparkType "Column"
                                , body = Just expectedFunctionBody
                                }
                    in
                    Expect.equal expectedFunctionDeclarationRec mappedFunctionDefinitionReturningRec
    in
    describe "FunctionGenerationTests"
        [ assertGenerationOfBasicFunction
        , assertGenerationOfFunctionReturningRecord
        ]
