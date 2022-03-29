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
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend
import Morphir.Elm.IncrementalFrontend.Codec as IncrementalFrontendCodec
import Morphir.File.FileChanges as FileChanges exposing (FileChanges)
import Morphir.File.FileChanges.Codec as FileChangesCodec
import Morphir.File.FileSnapshot as FileSnapshot exposing (FileSnapshot)
import Morphir.File.FileSnapshot.Codec as FileSnapshotCodec
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistroCodec
import Morphir.IR.Repo as Repo exposing (Error(..), Repo)
import Morphir.IR.SDK as SDK


port jsonDecodeError : String -> Cmd msg


port buildFromScratch : (Encode.Value -> msg) -> Sub msg


port buildIncrementally : (Encode.Value -> msg) -> Sub msg


port buildCompleted : Encode.Value -> Cmd msg


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
        BuildFromScratch jsonInput ->
            let
                decodeInput : Decode.Decoder BuildFromScratchInput
                decodeInput =
                    Decode.map3 BuildFromScratchInput
                        (Decode.field "options" FrontendCodec.decodeOptions)
                        (Decode.field "packageInfo" FrontendCodec.decodePackageInfo)
                        (Decode.field "fileSnapshot" FileSnapshotCodec.decodeFileSnapshot)

                keepElmFilesOnly : FileSnapshot -> FileSnapshot
                keepElmFilesOnly fileSnapshot =
                    fileSnapshot
                        |> FileSnapshot.filter
                            (\path _ ->
                                path |> String.endsWith ".elm"
                            )
            in
            case jsonInput |> Decode.decodeValue decodeInput of
                Ok input ->
                    Repo.empty input.packageInfo.name
                        -- Insert the SDK as a dependency
                        |> Repo.insertDependencySpecification SDK.packageName SDK.packageSpec
                        |> Result.mapError (IncrementalFrontend.RepoError >> List.singleton)
                        |> Result.andThen (IncrementalFrontend.applyFileChanges (keepElmFilesOnly input.fileSnapshot |> FileSnapshot.toInserts))
                        |> Result.map Repo.toDistribution
                        |> encodeResult (Encode.list IncrementalFrontendCodec.encodeError) DistroCodec.encodeVersionedDistribution
                        |> (\value -> ( model, buildCompleted value ))

                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> jsonDecodeError
                    )

        BuildIncrementally jsonInput ->
            let
                decodeInput : Decode.Decoder BuildIncrementallyInput
                decodeInput =
                    Decode.map4 BuildIncrementallyInput
                        (Decode.field "options" FrontendCodec.decodeOptions)
                        (Decode.field "packageInfo" FrontendCodec.decodePackageInfo)
                        (Decode.field "fileChanges" FileChangesCodec.decodeFileChanges)
                        (Decode.field "distribution" DistroCodec.decodeVersionedDistribution)

                keepElmFilesOnly : FileChanges -> FileChanges
                keepElmFilesOnly fileChanges =
                    fileChanges
                        |> FileChanges.filter
                            (\path _ ->
                                path |> String.endsWith ".elm"
                            )
            in
            case jsonInput |> Decode.decodeValue decodeInput of
                Ok input ->
                    input.distribution
                        |> Repo.fromDistribution
                        |> Result.mapError (IncrementalFrontend.RepoError >> List.singleton)
                        -- Insert the SDK as a dependency
                        |> Result.andThen
                            (Repo.insertDependencySpecification SDK.packageName SDK.packageSpec
                                >> Result.mapError (IncrementalFrontend.RepoError >> List.singleton)
                            )
                        |> Result.andThen (IncrementalFrontend.applyFileChanges (keepElmFilesOnly input.fileChanges))
                        |> Result.map Repo.toDistribution
                        |> encodeResult (Encode.list IncrementalFrontendCodec.encodeError) DistroCodec.encodeVersionedDistribution
                        |> (\value -> ( model, buildCompleted value ))

                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> jsonDecodeError
                    )


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch
        [ buildFromScratch BuildFromScratch
        , buildIncrementally BuildIncrementally
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
