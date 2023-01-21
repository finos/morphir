{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.Scala.Feature.TestBackend exposing (..)

{-| This module allows for the generation of a scala test suite from already existing morphir tests.
-}

import Dict
import Morphir.Correctness.Test as T
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal as ValueLiteral
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Scala.AST as Scala exposing (CompilationUnit)
import Morphir.Scala.Feature.Core as Scala
import Morphir.Type.Infer as Infer
import Set exposing (Set)


type alias Options =
    { includeGenericTests : Bool
    , includeScalaTests : Bool
    }


type TestKind
    = ScalaTest
    | GenericTest


type alias MorphirTestSuite =
    T.TestSuite


type alias PartiallySpecifiedTestCase =
    T.TestCase


type alias FullySpecifiedMorphirTestCase =
    { inputs : List RawValue
    , expectedOutput : RawValue
    , description : String
    }


type alias ScalaTestCase =
    { input : Scala.Value
    , expectedOutput : Scala.Value
    , description : Scala.Value
    }


type alias TestCaseFieldDecl =
    { name : String
    , tpe : Scala.Type
    }


sdkPath : List String
sdkPath =
    [ "morphir", "sdk" ]


scalaTestPath : List String
scalaTestPath =
    [ "org", "scalatest", "funsuite" ]


inputField : TestCaseFieldDecl
inputField =
    { name = "input"
    , tpe = Scala.TypeVar "Any"
    }


outputField : TestCaseFieldDecl
outputField =
    { name = "expectedOutput"
    , tpe = Scala.TypeVar "Any"
    }


descriptionField : TestCaseFieldDecl
descriptionField =
    { name = "description"
    , tpe = Scala.TypeRef sdkPath "String.String"
    }


{-| Entry point for mapping a Morphir test suite to scala. The morphir test suite is generated from the `morphir-tests.json`
and the params are: packageName, ir, includeScalaTest (generate the test cases for scala test), and the morphirTestSuite.
The TestCases are generated at the root of the scala package as `MorphirTests.scala` and may contain runnable test cases
if `includeScalaTest = True`.
-}
genTestSuite : Options -> PackageName -> IR -> MorphirTestSuite -> List CompilationUnit
genTestSuite opts packageName ir morphirTestSuite =
    let
        testsToGenerate : List ( TestKind, Bool )
        testsToGenerate =
            [ ( GenericTest, opts.includeGenericTests )
            , ( ScalaTest, opts.includeScalaTests )
            ]

        ( fullySpecifiedTestCases, _ ) =
            splitTestSuite morphirTestSuite

        scalaTestCases : List ScalaTestCase
        scalaTestCases =
            morphirTestCaseToScalaTestCase ir fullySpecifiedTestCases
    in
    testsToGenerate
        |> List.filterMap
            (\( kind, shouldGenerateForKind ) ->
                if shouldGenerateForKind then
                    Just
                        { dirPath =
                            List.concat
                                [ packageName |> List.map (Name.toCamelCase >> String.toLower)
                                , [ "_morphirtests" ]
                                ]
                        , fileName = kindToString kind ++ ".scala"
                        , packageDecl =
                            [ Path.toString (Name.toTitleCase >> String.toLower) "." packageName
                            , "_morphirtests"
                            ]
                        , imports = []
                        , typeDecls =
                            [ Scala.Documented (Just "Generated based on morphir-tests.json")
                                (createTestDecl kind scalaTestCases)
                            ]
                        }

                else
                    Nothing
            )


kindToString : TestKind -> String
kindToString testKind =
    case testKind of
        ScalaTest ->
            "ScalaTest"

        GenericTest ->
            "GenericTest"


createTestDecl : TestKind -> List ScalaTestCase -> Scala.Annotated Scala.TypeDecl
createTestDecl testKind scalaTestCases =
    let
        {- a case class for a test case:
           `case class TestCase(input: Any, output: Any, description: String)`
        -}
        testCaseClass : Scala.MemberDecl
        testCaseClass =
            Scala.MemberTypeDecl <|
                Scala.Class
                    { modifiers = [ Scala.Case ]
                    , typeArgs = []
                    , name = "TestCase"
                    , ctorArgs =
                        [ inputField, outputField, descriptionField ]
                            |> List.map
                                (\field ->
                                    { modifiers = []
                                    , tpe = field.tpe
                                    , name = field.name
                                    , defaultValue = Nothing
                                    }
                                )
                            |> List.singleton
                    , extends = []
                    , members = []
                    , body = []
                    }

        testCasesValDecl : Scala.MemberDecl
        testCasesValDecl =
            Scala.ValueDecl
                { modifiers = []
                , pattern = Scala.NamedMatch "testCases"
                , valueType = Nothing
                , value = scalaList (mapTestCases testKind scalaTestCases)
                }
    in
    case testKind of
        ScalaTest ->
            Scala.withoutAnnotation <|
                Scala.Class
                    { modifiers = []
                    , name = kindToString testKind
                    , typeArgs = []
                    , ctorArgs = []
                    , extends = [ Scala.TypeRef scalaTestPath "AnyFunSuite" ]
                    , members = []
                    , body = mapTestCases testKind scalaTestCases
                    }

        _ ->
            Scala.withoutAnnotation <|
                Scala.Object
                    { modifiers = []
                    , name = kindToString testKind
                    , extends = []
                    , members =
                        [ Scala.withoutAnnotation testCaseClass
                        , Scala.withoutAnnotation <|
                            testCasesValDecl
                        ]
                    , body = Nothing
                    }


{-| Take each morphir test case and map their inputs, output and description to scala values while
maintaining the record structure. This allows creation of different kinds of test without having to do
the value mappings again.
-}
morphirTestCaseToScalaTestCase : IR -> List ( FQName, FullySpecifiedMorphirTestCase ) -> List ScalaTestCase
morphirTestCaseToScalaTestCase ir fullySpecifiedMorphirTestCases =
    let
        mapper : Int -> ( FQName, FullySpecifiedMorphirTestCase ) -> ScalaTestCase
        mapper count ( fqn, testCase ) =
            let
                valueSpec : Value.Specification ()
                valueSpec =
                    IR.lookupValueSpecification fqn ir
                        |> Maybe.withDefault
                            (let
                                _ =
                                    Debug.log "Could not find FQN" fqn
                             in
                             Debug.todo "FQN should always exist in IR"
                            )

                applyArgsOnRef : List RawValue -> RawValue -> RawValue
                applyArgsOnRef args appliedSoFar =
                    case args of
                        [] ->
                            appliedSoFar

                        nextArg :: otherArgs ->
                            Value.Apply () appliedSoFar nextArg
                                |> applyArgsOnRef otherArgs

                toScalaVal : Maybe (Type.Type ()) -> RawValue -> Scala.Value
                toScalaVal maybeTpe val =
                    val
                        |> rawValueToTypedValue ir maybeTpe
                        |> Maybe.map (Scala.mapValue Set.empty)
                        |> Maybe.withDefault (mapRawValue Set.empty val)

                descriptionScalaValue : Scala.Value
                descriptionScalaValue =
                    let
                        ( path, name ) =
                            Scala.mapFQNameToPathAndName fqn
                    in
                    String.concat
                        [ String.join "." path
                        , "."
                        , Name.toCamelCase name
                        , " test" ++ String.fromInt count
                        , if testCase.description == "" then
                            ""

                          else
                            " : " ++ testCase.description
                        ]
                        |> Scala.StringLit
                        |> Scala.Literal
            in
            { input =
                applyArgsOnRef testCase.inputs (valueRef fqn)
                    |> toScalaVal Nothing
            , expectedOutput =
                testCase.expectedOutput
                    |> toScalaVal (Just valueSpec.output)
            , description = descriptionScalaValue
            }
    in
    fullySpecifiedMorphirTestCases
        |> List.indexedMap mapper


{-| Take a Morphir test suite and split it into two groups where the first group has all inputs specified,
and the second group contains some unspecified arguments.
-}
splitTestSuite : MorphirTestSuite -> ( List ( FQName, FullySpecifiedMorphirTestCase ), List ( FQName, PartiallySpecifiedTestCase ) )
splitTestSuite morphirTestSuite =
    let
        allInputsSpecified : PartiallySpecifiedTestCase -> Bool
        allInputsSpecified =
            List.all (\i -> i /= Nothing) << .inputs
    in
    morphirTestSuite
        |> Dict.toList
        |> List.foldl
            (\( fqn, allTestCases ) testCaseGroups ->
                allTestCases
                    |> List.foldl
                        (\testCase ( fullySpecifiedTestCases, partiallySpecifiedTestCases ) ->
                            if allInputsSpecified testCase then
                                ( ( fqn
                                  , { inputs = List.filterMap identity testCase.inputs
                                    , expectedOutput = testCase.expectedOutput
                                    , description = testCase.description
                                    }
                                  )
                                    :: fullySpecifiedTestCases
                                , partiallySpecifiedTestCases
                                )

                            else
                                ( fullySpecifiedTestCases, ( fqn, testCase ) :: partiallySpecifiedTestCases )
                        )
                        testCaseGroups
            )
            ( [], [] )


mapTestCases : TestKind -> List ScalaTestCase -> List Scala.Value
mapTestCases testKind scalaTestCases =
    scalaTestCases
        |> List.map (mapScalaTestCaseToScalaValue testKind)


{-| generates the appropriate testcase value depending on the TestKind
-}
mapScalaTestCaseToScalaValue : TestKind -> ScalaTestCase -> Scala.Value
mapScalaTestCaseToScalaValue testKind scalaTestCase =
    case testKind of
        ScalaTest ->
            Scala.Apply
                (applyOneArg (scalaVar "test") scalaTestCase.description)
                [ Scala.ArgValue Nothing <|
                    Scala.Block []
                        (applyOneArg
                            (applyOneArg (scalaVar "assertResult") scalaTestCase.expectedOutput)
                            scalaTestCase.input
                        )
                ]

        GenericTest ->
            Scala.Apply
                (Scala.Variable "TestCase")
                [ scalaTestCase.input
                    |> Scala.ArgValue Nothing
                , scalaTestCase.expectedOutput
                    |> Scala.ArgValue (Just outputField.name)
                , scalaTestCase.description
                    |> Scala.ArgValue (Just descriptionField.name)
                ]


{-| Infers the Type of a value using the Type Inferencer.
If a type is supplied to this function, it creates a value definition and then proceeds to infer the type.
If no type information is supplied, then it attempts to infer the type.
In case of an error while inferring the type, this returns a `Nothing`
-}
rawValueToTypedValue : IR -> Maybe (Type.Type ()) -> RawValue -> Maybe Value.TypedValue
rawValueToTypedValue ir valueType rawValue =
    let
        resultToValue : Result e (Value ta ( b, va )) -> Maybe (Value ta va)
        resultToValue res =
            case res of
                Ok v ->
                    v
                        |> Value.mapValueAttributes identity Tuple.second
                        |> Just

                Err err ->
                    let
                        _ =
                            Debug.log "Failed to infer type" err
                    in
                    Nothing
    in
    case valueType of
        Just tpe ->
            let
                valDef =
                    { inputTypes = []
                    , outputType = tpe
                    , body = rawValue
                    }
            in
            Infer.inferValueDefinition ir valDef
                |> Result.map .body
                |> resultToValue

        Nothing ->
            Infer.inferValue ir rawValue
                |> resultToValue


{-| map an untyped value to Scala.
Ignores certain values like lambdas because they can't exist as inputs or outputs.
-}
mapRawValue : Set Name -> Value () () -> Scala.Value
mapRawValue inScopeVars value =
    case value of
        Value.Literal _ literal ->
            let
                wrap : List String -> String -> Scala.Lit -> Scala.Value
                wrap modulePath moduleName lit =
                    Scala.Apply
                        (Scala.Ref modulePath moduleName)
                        [ Scala.ArgValue Nothing (Scala.Literal lit) ]
            in
            case literal of
                ValueLiteral.BoolLiteral v ->
                    Scala.Literal (Scala.BooleanLit v)

                ValueLiteral.CharLiteral v ->
                    wrap [ "morphir", "sdk", "Char" ] "from" (Scala.CharacterLit v)

                ValueLiteral.StringLiteral v ->
                    Scala.Literal (Scala.StringLit v)

                ValueLiteral.WholeNumberLiteral v ->
                    wrap [ "morphir", "sdk", "Basics" ] "Int" (Scala.IntegerLit v)

                ValueLiteral.FloatLiteral v ->
                    wrap [ "morphir", "sdk", "Basics" ] "Float" (Scala.FloatLit v)

                ValueLiteral.DecimalLiteral decLit ->
                    Scala.Literal (Scala.DecimalLit decLit)

        Value.Constructor _ fQName ->
            let
                ( path, name ) =
                    Scala.mapFQNameToPathAndName fQName
            in
            Scala.Ref path (Name.toTitleCase name)

        Value.Tuple _ elemValues ->
            Scala.Tuple
                (elemValues |> List.map (mapRawValue inScopeVars))

        Value.List _ itemValues ->
            Scala.Apply
                (Scala.Ref [ "morphir", "sdk" ] "List")
                (itemValues
                    |> List.map (mapRawValue inScopeVars)
                    |> List.map (Scala.ArgValue Nothing)
                )

        Value.Record _ fieldValues ->
            Scala.StructuralValue
                (fieldValues
                    |> Dict.toList
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            ( Scala.mapValueName fieldName, mapRawValue inScopeVars fieldValue )
                        )
                )

        Value.Variable _ name ->
            Scala.Variable (Scala.mapValueName name)

        Value.Reference _ fQName ->
            let
                ( path, name ) =
                    Scala.mapFQNameToPathAndName fQName
            in
            Scala.Ref path (Scala.mapValueName name)

        Value.Field _ subjectValue fieldName ->
            Scala.Select (mapRawValue inScopeVars subjectValue) (Scala.mapValueName fieldName)

        Value.FieldFunction _ fieldName ->
            Scala.Select Scala.Wildcard (Scala.mapValueName fieldName)

        Value.Apply _ applyFun applyArg ->
            Scala.Apply
                (mapRawValue inScopeVars applyFun)
                [ Scala.ArgValue Nothing (mapRawValue inScopeVars applyArg)
                ]

        Value.Unit _ ->
            Scala.Unit

        _ ->
            Debug.todo "Not supported"


valueRef : FQName -> RawValue
valueRef fqn =
    Value.Reference () fqn


apply : Scala.Value -> List Scala.Value -> Scala.Value
apply target args =
    args
        |> List.map (Scala.ArgValue Nothing)
        |> Scala.Apply target


applyOneArg : Scala.Value -> Scala.Value -> Scala.Value
applyOneArg target =
    Scala.ArgValue Nothing
        >> List.singleton
        >> Scala.Apply target


scalaVar : Scala.Name -> Scala.Value
scalaVar =
    Scala.Variable


scalaList : List Scala.Value -> Scala.Value
scalaList lst =
    lst
        |> List.map (Scala.ArgValue Nothing)
        |> Scala.Apply (Scala.Ref sdkPath "List")
