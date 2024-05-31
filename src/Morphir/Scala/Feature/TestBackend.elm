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
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.SDK.ResultList as ResultList
import Morphir.Scala.AST as Scala exposing (CompilationUnit)
import Morphir.Scala.Feature.Core as Scala
import Morphir.Type.Infer as Infer
import Set exposing (Set)


type alias Options =
    { includeGenericTests : Bool
    , includeScalaTests : Bool
    }


{-| Representative of the different kinds of test suite that can be generated.
-}
type TestKind
    = ScalaTest
    | GenericTest


type alias MorphirTestSuite =
    T.TestSuite


{-| A morphir test case containing a list of args for a yet-to-be-specified function,
the expected output value of the function, and the test description.
The `input` type parameter allows for variations of the args because Morphir supports test cases with
partially specified args
-}
type alias MorphirTestCase input =
    { inputs : List input
    , expectedOutput : RawValue
    , description : String
    }


type alias PartiallySpecified =
    MorphirTestCase (Maybe RawValue)


type alias FullySpecified =
    MorphirTestCase RawValue


{-| A representation of a test case in scala. The reason for this structure is to provide a way of
processing scala values just once, but maintaining the different parts of the test case.
The fields are:

  - subjectWithInputsApplied: an invocation that will produce the actual output
  - expectedOutput: the expected output
  - description: a test description

-}
type alias ScalaTestCase =
    { subjectWithInputsApplied : Scala.Value
    , expectedOutput : Scala.Value
    , description : Scala.Value
    }


type alias TestCaseFieldDecl =
    { name : String
    , tpe : Scala.Type
    }


type Error
    = TestError String
    | InferenceError Infer.TypeError


type alias Errors =
    List Error


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
genTestSuite : Options -> PackageName -> Distribution -> MorphirTestSuite -> Result Errors (List CompilationUnit)
genTestSuite opts packageName distro morphirTestSuite =
    let
        testsToGenerate : List ( TestKind, Bool )
        testsToGenerate =
            [ ( GenericTest, opts.includeGenericTests )
            , ( ScalaTest, opts.includeScalaTests )
            ]

        ( fullySpecifiedTestCases, _ ) =
            splitTestSuite morphirTestSuite

        scalaTestCasesResult : Result Error (List ScalaTestCase)
        scalaTestCasesResult =
            morphirTestCaseToScalaTestCase distro fullySpecifiedTestCases
    in
    testsToGenerate
        |> List.filterMap
            (\( kind, shouldGenerateForKind ) ->
                if shouldGenerateForKind then
                    scalaTestCasesResult
                        |> Result.map
                            (\scalaTestCases ->
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
                            )
                        |> Just

                else
                    Nothing
            )
        |> ResultList.keepAllErrors


kindToString : TestKind -> String
kindToString testKind =
    case testKind of
        ScalaTest ->
            "ScalaTest"

        GenericTest ->
            "GenericTest"


{-| Create a case class for a ScalaTestCase.
-}
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
morphirTestCaseToScalaTestCase : Distribution -> List ( FQName, FullySpecified ) -> Result Error (List ScalaTestCase)
morphirTestCaseToScalaTestCase ir fullySpecifiedMorphirTestCases =
    let
        mapper : Int -> ( FQName, FullySpecified ) -> Result Error ScalaTestCase
        mapper count ( fqn, testCase ) =
            let
                valueSpecResult : Result Error (Value.Specification ())
                valueSpecResult =
                    Distribution.lookupValueSpecification fqn ir
                        |> Result.fromMaybe (TestError ("Could not find a function with FQN: " ++ FQName.toString fqn))

                applyArgsOnRef : List RawValue -> RawValue -> RawValue
                applyArgsOnRef args appliedSoFar =
                    case args of
                        [] ->
                            appliedSoFar

                        nextArg :: otherArgs ->
                            Value.Apply () appliedSoFar nextArg
                                |> applyArgsOnRef otherArgs

                toScalaVal : Maybe (Type.Type ()) -> RawValue -> Result Error Scala.Value
                toScalaVal maybeTpe val =
                    val
                        |> rawValueToTypedValue ir maybeTpe
                        |> Result.map (Scala.mapValue Set.empty)

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
            Result.map2
                (\input output ->
                    { subjectWithInputsApplied = input
                    , expectedOutput =
                        output
                    , description = descriptionScalaValue
                    }
                )
                (applyArgsOnRef testCase.inputs (valueRef fqn)
                    |> toScalaVal Nothing
                )
                (valueSpecResult
                    |> Result.andThen
                        (\valSpec ->
                            testCase.expectedOutput
                                |> toScalaVal (Just valSpec.output)
                        )
                )
    in
    fullySpecifiedMorphirTestCases
        |> List.indexedMap mapper
        |> ResultList.keepFirstError


{-| Take a Morphir test suite and split it into two groups where the first group has all inputs specified,
and the second group contains some unspecified arguments.
-}
splitTestSuite : MorphirTestSuite -> ( List ( FQName, FullySpecified ), List ( FQName, PartiallySpecified ) )
splitTestSuite morphirTestSuite =
    let
        allInputsSpecified : PartiallySpecified -> Bool
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
                            scalaTestCase.subjectWithInputsApplied
                        )
                ]

        GenericTest ->
            Scala.Apply
                (Scala.Variable "TestCase")
                [ scalaTestCase.subjectWithInputsApplied
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
rawValueToTypedValue : Distribution -> Maybe (Type.Type ()) -> RawValue -> Result Error Value.TypedValue
rawValueToTypedValue ir valueType rawValue =
    let
        mapInferResult : Result Infer.TypeError (Value () ( b, Type.Type () )) -> Result Error (Value () (Type.Type ()))
        mapInferResult res =
            res
                |> Result.map (Value.mapValueAttributes identity Tuple.second)
                |> Result.mapError InferenceError
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
                |> mapInferResult

        Nothing ->
            Infer.inferValue ir rawValue
                |> mapInferResult


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
