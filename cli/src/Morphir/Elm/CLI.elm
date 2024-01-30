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


port module Morphir.Elm.CLI exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (field, string)
import Json.Encode as Encode
import Morphir.Compiler as Compiler
import Morphir.Compiler.Codec as CompilerCodec
import Morphir.Correctness.Codec exposing (decodeTestSuite)
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Codec as FrontendCodec
import Morphir.Elm.Target exposing (BackendOptions, decodeOptions, mapDistribution)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.FileMap.Codec exposing (encodeFileMap)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.FormatVersion.Codec as DistributionCodec
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.SDK as SDK
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.SDK.ResultList as ResultList
import Morphir.Type.Infer as Infer
import Morphir.Value.Interpreter exposing (evaluateFunctionValue)


port packageDefinitionFromSource : (( Decode.Value, Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port jsonDecodeError : String -> Cmd msg


port generate : (( Decode.Value, Decode.Value ) -> msg) -> Sub msg


port generateResult : Encode.Value -> Cmd msg


port runTestCases : (( Decode.Value, Decode.Value ) -> msg) -> Sub msg


port runTestCasesResult : Encode.Value -> Cmd msg


port runTestCasesResultError : Encode.Value -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, Decode.Value, List SourceFile )
    | Generate ( Decode.Value, Decode.Value )
    | RunTestCases ( Decode.Value, Decode.Value )


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


update : Msg -> () -> ( (), Cmd Msg )
update msg model =
    case msg of
        PackageDefinitionFromSource ( optionsJson, packageInfoJson, sourceFiles ) ->
            let
                inputResult : Result Decode.Error ( Frontend.Options, PackageInfo )
                inputResult =
                    Result.map2 Tuple.pair
                        (Decode.decodeValue FrontendCodec.decodeOptions optionsJson)
                        (Decode.decodeValue FrontendCodec.decodePackageInfo packageInfoJson)
            in
            case inputResult of
                Ok ( opts, packageInfo ) ->
                    let
                        relevantSourceFiles : List SourceFile
                        relevantSourceFiles =
                            sourceFiles
                                |> List.filter
                                    (\sourceFile ->
                                        not
                                            (String.contains "Morphir/SDK" sourceFile.path
                                                || String.contains "Morphir\\SDK" sourceFile.path
                                            )
                                    )

                        frontendResult : Result (List Compiler.Error) (Package.Definition Frontend.SourceLocation Frontend.SourceLocation)
                        frontendResult =
                            Frontend.mapSource opts packageInfo Dict.empty relevantSourceFiles

                        typedResult : Result (List Compiler.Error) (Package.Definition () ( Frontend.SourceLocation, Type () ))
                        typedResult =
                            frontendResult
                                |> Result.andThen
                                    (\packageDef ->
                                        let
                                            thisPackageSpec : Package.Specification ()
                                            thisPackageSpec =
                                                packageDef
                                                    |> Package.definitionToSpecificationWithPrivate
                                                    |> Package.mapSpecificationAttributes (\_ -> ())

                                            ir : Distribution
                                            ir =
                                                Library
                                                    [ [ "empty" ] ]
                                                    (Frontend.defaultDependencies
                                                        |> Dict.insert packageInfo.name thisPackageSpec
                                                    )
                                                    Package.emptyDefinition
                                        in
                                        packageDef
                                            |> Package.mapDefinitionAttributes (\_ -> ()) identity
                                            |> Infer.inferPackageDefinition ir
                                    )
                    in
                    ( model
                    , typedResult
                        |> Result.map (Package.mapDefinitionAttributes identity (\( _, tpe ) -> tpe))
                        |> Result.map (Distribution.Library packageInfo.name Dict.empty)
                        |> encodeResult (Encode.list CompilerCodec.encodeError) DistributionCodec.encodeVersionedDistribution
                        |> packageDefinitionFromSourceResult
                    )

                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> jsonDecodeError
                    )

        Generate ( optionsJson, packageDistJson ) ->
            let
                targetOption : Result Decode.Error String
                targetOption =
                    Decode.decodeValue (field "target" string) optionsJson

                optionsResult : Result Decode.Error BackendOptions
                optionsResult =
                    Decode.decodeValue (decodeOptions targetOption) optionsJson

                packageDistroResult : Result Decode.Error Distribution
                packageDistroResult =
                    Decode.decodeValue DistributionCodec.decodeVersionedDistribution packageDistJson
            in
            case Result.map2 Tuple.pair optionsResult packageDistroResult of
                Ok ( options, packageDist ) ->
                    let
                        enrichedDistro : Distribution
                        enrichedDistro =
                            case packageDist of
                                Library packageName dependencies packageDef ->
                                    Library packageName (Dict.union Frontend.defaultDependencies dependencies) packageDef

                        fileMap : Result Encode.Value FileMap
                        fileMap =
                            mapDistribution options enrichedDistro
                    in
                    ( model
                    , fileMap
                        |> encodeResult identity encodeFileMap
                        |> generateResult
                    )

                Err errorMessage ->
                    ( model, errorMessage |> Decode.errorToString |> jsonDecodeError )

        RunTestCases ( distributionJson, testSuiteJson ) ->
            let
                resultIR : Result Decode.Error Distribution
                resultIR =
                    case distributionJson |> Decode.decodeValue DistributionCodec.decodeVersionedDistribution of
                        Ok packageDist ->
                            case packageDist of
                                Library packageName dependencies packageDef ->
                                    Ok (Library packageName (Dict.union Frontend.defaultDependencies dependencies) packageDef)

                        Err err ->
                            Err err
            in
            case resultIR of
                Ok ir ->
                    case testSuiteJson |> Decode.decodeValue (decodeTestSuite ir) of
                        Ok testSuite ->
                            let
                                finalResult =
                                    testSuite
                                        |> Dict.toList
                                        |> List.map
                                            (\( functionName, testCaseList ) ->
                                                let
                                                    totalTestCase =
                                                        List.length testCaseList

                                                    resultList : List ( String, Encode.Value )
                                                    resultList =
                                                        testCaseList
                                                            |> List.map
                                                                (\testCase ->
                                                                    case evaluateFunctionValue SDK.nativeFunctions ir functionName testCase.inputs of
                                                                        Ok rawValue ->
                                                                            if rawValue == testCase.expectedOutput then
                                                                                ( "PASS"
                                                                                , Encode.object
                                                                                    [ ( "Expected Output", testCase.expectedOutput |> Value.toString |> Encode.string )
                                                                                    , ( "Actual Output", rawValue |> Value.toString |> Encode.string )
                                                                                    ]
                                                                                )

                                                                            else
                                                                                ( "FAIL"
                                                                                , Encode.object
                                                                                    [ ( "Expected Output", testCase.expectedOutput |> Value.toString |> Encode.string )
                                                                                    , ( "Actual Output", rawValue |> Value.toString |> Encode.string )
                                                                                    ]
                                                                                )

                                                                        Err error ->
                                                                            ( "FAIL"
                                                                            , Encode.object
                                                                                [ ( "Expected Output", testCase.expectedOutput |> Value.toString |> Encode.string )
                                                                                , ( "Actual Output", Debug.toString error |> Encode.string )
                                                                                ]
                                                                            )
                                                                )

                                                    ( passedList, failList ) =
                                                        resultList
                                                            |> List.partition
                                                                (\( status, encodedJson ) ->
                                                                    if status == "PASS" then
                                                                        True

                                                                    else
                                                                        False
                                                                )
                                                in
                                                if List.length failList == 0 then
                                                    Ok
                                                        (Encode.object
                                                            [ ( "Function Name"
                                                              , functionName |> FQName.toString |> Encode.string
                                                              )
                                                            , ( "Total TestCases"
                                                              , totalTestCase |> Encode.int
                                                              )
                                                            , ( "Pass TestCases"
                                                              , passedList |> List.length |> Encode.int
                                                              )
                                                            , ( "Fail TestCases List", failList |> List.map Tuple.second |> Encode.list identity )
                                                            ]
                                                        )

                                                else
                                                    Err
                                                        (Encode.object
                                                            [ ( "Function Name"
                                                              , functionName |> FQName.toString |> Encode.string
                                                              )
                                                            , ( "Total TestCases"
                                                              , totalTestCase |> Encode.int
                                                              )
                                                            , ( "Fail TestCases"
                                                              , failList |> List.length |> Encode.int
                                                              )
                                                            , ( "Fail TestCases List", failList |> List.map Tuple.second |> Encode.list identity )
                                                            ]
                                                        )
                                            )
                                        |> ResultList.keepAllErrors
                            in
                            case finalResult of
                                Ok passList ->
                                    ( model, passList |> Encode.list identity |> runTestCasesResult )

                                Err failList ->
                                    ( model, failList |> Encode.list identity |> runTestCasesResultError )

                        Err errorMessage ->
                            ( model, errorMessage |> Decode.errorToString |> jsonDecodeError )

                Err errorMessage ->
                    ( model, errorMessage |> Decode.errorToString |> jsonDecodeError )


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch
        [ packageDefinitionFromSource PackageDefinitionFromSource
        , generate Generate
        , runTestCases RunTestCases
        ]


encodeResult : (e -> Encode.Value) -> (a -> Encode.Value) -> Result e a -> Encode.Value
encodeResult encodeErr encodeValue result =
    case result of
        Ok a ->
            Encode.list identity
                [ Encode.null
                , encodeValue a
                ]

        Err e ->
            Encode.list identity
                [ encodeErr e
                , Encode.null
                ]
