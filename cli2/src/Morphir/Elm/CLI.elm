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
import Morphir.File.FileChanges exposing (FileChanges)
import Morphir.File.FileChanges.Codec as FileChangesCodec
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistroCodec
import Morphir.IR.Repo as Repo exposing (Error(..), Repo)
import Morphir.IR.Repo.Codec as RepoCodec


port jsonDecodeError : String -> Cmd msg


port packageDefinitionFromSource : (( Decode.Value, Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port incrementalBuild :
    ({ optionsJson : Decode.Value
     , packageInfoJson : Decode.Value
     , fileChangesJson : Decode.Value
     , distribution : Distribution
     }
     -> msg
    )
    -> Sub msg


port incrementalBuildResult : Encode.Value -> Cmd msg


type alias PassedValues =
    { optionsJson : Decode.Value
    , packageInfoJson : Decode.Value
    , fileChangesJson : Decode.Value
    , distribution : Distribution
    }


type Msg
    = PackageDefinitionFromSource ( Decode.Value, Decode.Value, List SourceFile )
    | IncrementalBuild PassedValues


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
                Ok ( _, packageInfo ) ->
                    let
                        emptyRepo : Repo
                        emptyRepo =
                            Repo.empty packageInfo.name
                    in
                    -- add source file processing
                    ( model
                    , emptyRepo
                        |> Repo.toDistribution
                        |> DistroCodec.encodeDistribution
                        |> packageDefinitionFromSourceResult
                    )

                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> jsonDecodeError
                    )

        IncrementalBuild { optionsJson, packageInfoJson, fileChangesJson, distribution } ->
            let
                decodeInputs : Result Decode.Error ( Frontend.Options, PackageInfo, FileChanges )
                decodeInputs =
                    Result.map3
                        (\options packageInfo fileChanges -> ( options, packageInfo, fileChanges ))
                        (Decode.decodeValue FrontendCodec.decodeOptions optionsJson)
                        (Decode.decodeValue FrontendCodec.decodePackageInfo packageInfoJson)
                        (Decode.decodeValue FileChangesCodec.decodeFileChanges fileChangesJson)

                repoFromDistribution : Result Repo.Errors Repo
                repoFromDistribution =
                    Repo.fromDistribution distribution
            in
            case decodeInputs of
                Ok ( _, _, fileChanges ) ->
                    repoFromDistribution
                        |> Result.andThen (Repo.applyFileChanges fileChanges)
                        |> Result.map Repo.toDistribution
                        |> encodeResult (Encode.list RepoCodec.encodeError) DistroCodec.encodeVersionedDistribution
                        |> (\value -> ( model, incrementalBuildResult value ))

                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> jsonDecodeError
                    )


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch
        [ packageDefinitionFromSource PackageDefinitionFromSource
        , incrementalBuild IncrementalBuild
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
