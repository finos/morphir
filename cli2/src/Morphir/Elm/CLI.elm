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
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistroCodec
import Morphir.IR.Repo as Repo exposing (Error(..), Repo)
import Morphir.IR.SDK as SDK


port jsonDecodeError : String -> Cmd msg


port buildIncrementally : (Encode.Value -> msg) -> Sub msg


port buildIncrementallyCompleted : Encode.Value -> Cmd msg


type alias IncrementalBuildInput =
    { options : Frontend.Options
    , packageInfo : PackageInfo
    , fileChanges : FileChanges
    , distribution : Maybe Distribution
    }


type Msg
    = BuildIncrementally Decode.Value


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
        BuildIncrementally incrementalBuildInputJson ->
            let
                decodeInputs : Decode.Decoder IncrementalBuildInput
                decodeInputs =
                    Decode.map4
                        IncrementalBuildInput
                        (Decode.field "options" FrontendCodec.decodeOptions)
                        (Decode.field "packageInfo" FrontendCodec.decodePackageInfo)
                        (Decode.field "fileChanges" FileChangesCodec.decodeFileChanges)
                        (Decode.field "distribution" (Decode.maybe DistroCodec.decodeVersionedDistribution))

                keepElmFilesOnly : FileChanges -> FileChanges
                keepElmFilesOnly fileChanges =
                    fileChanges
                        |> FileChanges.filter
                            (\path _ ->
                                path |> String.endsWith ".elm"
                            )
            in
            case incrementalBuildInputJson |> Decode.decodeValue decodeInputs of
                Ok input ->
                    case input.distribution of
                        Just distribution ->
                            distribution
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
                                |> (\value -> ( model, buildIncrementallyCompleted value ))

                        Nothing ->
                            Repo.empty input.packageInfo.name
                                -- Insert the SDK as a dependency
                                |> Repo.insertDependencySpecification SDK.packageName SDK.packageSpec
                                |> Result.mapError (IncrementalFrontend.RepoError >> List.singleton)
                                |> Result.andThen (IncrementalFrontend.applyFileChanges (keepElmFilesOnly input.fileChanges))
                                |> Result.map Repo.toDistribution
                                |> encodeResult (Encode.list IncrementalFrontendCodec.encodeError) DistroCodec.encodeVersionedDistribution
                                |> (\value -> ( model, buildIncrementallyCompleted value ))

                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> jsonDecodeError
                    )


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch
        [ buildIncrementally BuildIncrementally
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
