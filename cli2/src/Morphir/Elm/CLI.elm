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

import Dict
import Json.Decode as Decode exposing (field, string)
import Json.Encode as Encode
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Codec as FrontendCodec
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend exposing (Errors, ModuleChange(..), OrderedFileChanges)
import Morphir.Elm.IncrementalFrontend.Codec as IncrementalFrontendCodec
import Morphir.Elm.Target exposing (decodeOptions, mapDistribution)
import Morphir.File.FileChanges as FileChanges exposing (FileChanges)
import Morphir.File.FileChanges.Codec as FileChangesCodec
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.FileMap.Codec exposing (encodeFileMap)
import Morphir.File.FileSnapshot as FileSnapshot exposing (FileSnapshot)
import Morphir.File.FileSnapshot.Codec as FileSnapshotCodec
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistroCodec
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Repo as Repo exposing (Error(..), Repo)
import Morphir.IR.SDK as SDK
import Morphir.Stats.Backend as Stats
import Process
import Task


port decodeFailed : String -> Cmd msg


port buildFromScratch : (Encode.Value -> msg) -> Sub msg


port buildIncrementally : (Encode.Value -> msg) -> Sub msg


port buildCompleted : Encode.Value -> Cmd msg


port buildFailed : Encode.Value -> Cmd msg


port reportProgress : String -> Cmd msg


port jsonDecodeError : String -> Cmd msg


port generate : (( Decode.Value, Decode.Value ) -> msg) -> Sub msg


port generateResult : Encode.Value -> Cmd msg


port stats : (Decode.Value -> msg) -> Sub msg


port statsResult : Encode.Value -> Cmd msg


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch
        [ buildFromScratch BuildFromScratch
        , buildIncrementally BuildIncrementally
        , generate Generate
        , stats Stats
        ]


type alias BuildFromScratchInput =
    { options : Frontend.Options
    , packageInfo : PackageInfo
    , fileSnapshot : FileSnapshot
    }


type alias BuildIncrementallyInput =
    { options : Frontend.Options
    , packageInfo : PackageInfo
    , fileChanges : FileChanges
    , distribution : Distribution
    }


type Msg
    = BuildFromScratch Decode.Value
    | BuildIncrementally Decode.Value
    | OrderFileChanges PackageName PackageInfo Frontend.Options FileChanges Repo
    | ApplyFileChanges PackageInfo Frontend.Options (List ModuleChange) Repo
    | Generate ( Decode.Value, Decode.Value )
    | Stats Decode.Value


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


update : Msg -> () -> ( (), Cmd Msg )
update msg model =
    ( model, Cmd.batch [ process msg, report msg ] )


process : Msg -> Cmd Msg
process msg =
    case msg of
        BuildFromScratch jsonInput ->
            let
                decodeInput : Decode.Decoder BuildFromScratchInput
                decodeInput =
                    Decode.map3 BuildFromScratchInput
                        (Decode.field "options" FrontendCodec.decodeOptions)
                        (Decode.field "packageInfo" FrontendCodec.decodePackageInfo)
                        (Decode.field "fileSnapshot" FileSnapshotCodec.decodeFileSnapshot)
            in
            case jsonInput |> Decode.decodeValue decodeInput of
                Ok input ->
                    Repo.empty input.packageInfo.name
                        |> Repo.insertDependencySpecification SDK.packageName SDK.packageSpec
                        |> Result.mapError (IncrementalFrontend.RepoError "Error while building repo." >> List.singleton)
                        |> Result.map
                            (OrderFileChanges input.packageInfo.name
                                input.packageInfo
                                input.options
                                (input.fileSnapshot |> FileSnapshot.toInserts |> keepElmFilesOnly)
                            )
                        |> failOrProceed

                Err errorMessage ->
                    errorMessage
                        |> Decode.errorToString
                        |> decodeFailed

        BuildIncrementally jsonInput ->
            let
                decodeInput : Decode.Decoder BuildIncrementallyInput
                decodeInput =
                    Decode.map4 BuildIncrementallyInput
                        (Decode.field "options" FrontendCodec.decodeOptions)
                        (Decode.field "packageInfo" FrontendCodec.decodePackageInfo)
                        (Decode.field "fileChanges" FileChangesCodec.decodeFileChanges)
                        (Decode.field "distribution" DistroCodec.decodeVersionedDistribution)
            in
            case jsonInput |> Decode.decodeValue decodeInput of
                Ok input ->
                    input.distribution
                        |> Distribution.insertDependency SDK.packageName SDK.packageSpec
                        |> Repo.fromDistribution
                        |> Result.mapError (IncrementalFrontend.RepoError "Error while building repo." >> List.singleton)
                        |> Result.map
                            (OrderFileChanges input.packageInfo.name
                                input.packageInfo
                                input.options
                                (input.fileChanges |> keepElmFilesOnly)
                            )
                        |> failOrProceed

                Err errorMessage ->
                    errorMessage
                        |> Decode.errorToString
                        |> decodeFailed

        OrderFileChanges packageName packageInfo opts fileChanges repo ->
            IncrementalFrontend.orderFileChanges packageName repo fileChanges
                |> Result.map (\orderedModuleChanges -> ApplyFileChanges packageInfo opts orderedModuleChanges repo)
                |> failOrProceed

        ApplyFileChanges packageInfo opts orderedModuleChanges repo ->
            IncrementalFrontend.applyFileChanges packageInfo.name orderedModuleChanges opts packageInfo.exposedModules repo
                |> returnDistribution

        Generate ( optionsJson, packageDistJson ) ->
            let
                targetOption =
                    Decode.decodeValue (field "target" string) optionsJson

                optionsResult =
                    Decode.decodeValue (decodeOptions targetOption) optionsJson

                packageDistroResult =
                    Decode.decodeValue DistroCodec.decodeVersionedDistribution packageDistJson
            in
            case Result.map2 Tuple.pair optionsResult packageDistroResult of
                Ok ( options, packageDist ) ->
                    let
                        enrichedDistro =
                            case packageDist of
                                Library packageName dependencies packageDef ->
                                    Library packageName (Dict.union Frontend.defaultDependencies dependencies) packageDef

                        fileMap : FileMap
                        fileMap =
                            mapDistribution options enrichedDistro
                    in
                    fileMap |> Ok |> encodeResult Encode.string encodeFileMap |> generateResult

                Err errorMessage ->
                    errorMessage |> Decode.errorToString |> jsonDecodeError

        Stats packageDistJson ->
            let
                packageDistroResult =
                    Decode.decodeValue DistroCodec.decodeVersionedDistribution packageDistJson
            in
            case packageDistroResult of
                Ok packageDist ->
                    let
                        enrichedDistro =
                            case packageDist of
                                Library packageName dependencies packageDef ->
                                    Library packageName (Dict.union Frontend.defaultDependencies dependencies) packageDef

                        fileMap : FileMap
                        fileMap =
                            Stats.collectFeaturesFromDistribution enrichedDistro
                    in
                    fileMap |> Ok |> encodeResult Encode.string encodeFileMap |> statsResult

                Err errorMessage ->
                    errorMessage |> Decode.errorToString |> jsonDecodeError


report : Msg -> Cmd Msg
report msg =
    case msg of
        BuildFromScratch _ ->
            reportProgress "Building from scratch ..."

        BuildIncrementally _ ->
            reportProgress "Building incrementally ..."

        OrderFileChanges _ _ _ _ _ ->
            reportProgress "Parsing files and ordering file changes"

        ApplyFileChanges _ _ orderedModuleChanges _ ->
            reportProgress
                (String.concat
                    [ "Applying file changes in the following order:"
                    , "\n  - "
                    , orderedModuleChanges
                        |> List.map
                            (\moduleChange ->
                                case moduleChange of
                                    ModuleInsert moduleName _ ->
                                        "Insert: " ++ (moduleName |> Path.toString Name.toTitleCase ".")

                                    ModuleUpdate moduleName _ ->
                                        "Update: " ++ (moduleName |> Path.toString Name.toTitleCase ".")

                                    ModuleDelete moduleName ->
                                        "Delete: " ++ (moduleName |> Path.toString Name.toTitleCase ".")
                            )
                        |> String.join "\n  - "
                    ]
                )

        Generate ( optionJson, packageDistJson ) ->
            reportProgress " Generating target code from IR ..."

        Stats _ ->
            reportProgress "Generating stats from IR ..."


keepElmFilesOnly : FileChanges -> FileChanges
keepElmFilesOnly fileChanges =
    fileChanges
        |> FileChanges.filter
            (\path _ ->
                path |> String.endsWith ".elm"
            )


returnDistribution : Result IncrementalFrontend.Errors Repo -> Cmd Msg
returnDistribution repoResult =
    let
        removePackageDependencies (Library packageName _ packageDefinition) =
            Library packageName Dict.empty packageDefinition
    in
    repoResult
        |> Result.map Repo.toDistribution
        |> Result.map removePackageDependencies
        |> encodeResult (Encode.list IncrementalFrontendCodec.encodeError) DistroCodec.encodeVersionedDistribution
        |> buildCompleted


failOrProceed : Result IncrementalFrontend.Errors Msg -> Cmd Msg
failOrProceed msgResult =
    case msgResult of
        Ok msg ->
            Process.sleep 0 |> Task.perform (always msg)

        Err error ->
            Encode.list IncrementalFrontendCodec.encodeError error |> buildFailed


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
