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

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Codec as FrontendCodec
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend exposing (Errors, OrderedFileChanges)
import Morphir.Elm.IncrementalFrontend.Codec as IncrementalFrontendCodec
import Morphir.File.FileChanges as FileChanges exposing (FileChanges)
import Morphir.File.FileChanges.Codec as FileChangesCodec
import Morphir.File.FileSnapshot as FileSnapshot exposing (FileSnapshot)
import Morphir.File.FileSnapshot.Codec as FileSnapshotCodec
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistroCodec
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Repo as Repo exposing (Error(..), Repo)
import Morphir.IR.SDK as SDK
import Process
import Task


port decodeFailed : String -> Cmd msg


port buildFromScratch : (Encode.Value -> msg) -> Sub msg


port buildIncrementally : (Encode.Value -> msg) -> Sub msg


port buildCompleted : Encode.Value -> Cmd msg


port buildFailed : Encode.Value -> Cmd msg


port reportProgress : String -> Cmd msg


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch
        [ buildFromScratch BuildFromScratch
        , buildIncrementally BuildIncrementally
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
    | OrderFileChanges PackageName FileChanges Repo
    | ApplyFileChanges OrderedFileChanges Repo


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
                        |> Repo.fromDistribution
                        |> Result.andThen (Repo.insertDependencySpecification SDK.packageName SDK.packageSpec)
                        |> Result.mapError (IncrementalFrontend.RepoError "Error while building repo." >> List.singleton)
                        |> Result.map
                            (OrderFileChanges input.packageInfo.name
                                (input.fileChanges |> keepElmFilesOnly)
                            )
                        |> failOrProceed

                Err errorMessage ->
                    errorMessage
                        |> Decode.errorToString
                        |> decodeFailed

        OrderFileChanges packageName fileChanges repo ->
            IncrementalFrontend.orderFileChanges packageName fileChanges
                |> Result.map (\orderedFileChanges -> ApplyFileChanges orderedFileChanges repo)
                |> failOrProceed

        ApplyFileChanges orderedFileChanges repo ->
            IncrementalFrontend.applyFileChanges orderedFileChanges repo
                |> returnDistribution


report : Msg -> Cmd Msg
report msg =
    case msg of
        BuildFromScratch value ->
            reportProgress "Building from scratch"

        BuildIncrementally value ->
            reportProgress "Building incrementally"

        OrderFileChanges packageName fileChanges repo ->
            reportProgress "Parsing files and ordering file changes"

        ApplyFileChanges orderedFileChanges repo ->
            reportProgress
                (String.concat
                    [ "Applying file changes in the following order:\n"
                    , "  Additions:\n  - "
                    , orderedFileChanges.insertsAndUpdates
                        |> List.map (\( moduleName, _ ) -> moduleName |> Path.toString Name.toTitleCase ".")
                        |> String.join "\n  - "
                    ]
                )


keepElmFilesOnly : FileChanges -> FileChanges
keepElmFilesOnly fileChanges =
    fileChanges
        |> FileChanges.filter
            (\path _ ->
                path |> String.endsWith ".elm"
            )


returnDistribution : Result IncrementalFrontend.Errors Repo -> Cmd Msg
returnDistribution repoResult =
    repoResult
        |> Result.map Repo.toDistribution
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
