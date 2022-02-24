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
import Morphir.Compiler as Compiler
import Morphir.Compiler.Codec as CompilerCodec
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Codec as FrontendCodec
import Morphir.File.FileChanges exposing (FileChanges)
import Morphir.File.FileChanges.Codec as FileChangesCodec
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistroCodec
import Morphir.IR.Repo as Repo exposing (Error(..), Repo)


port jsonDecodeError : String -> Cmd msg


port packageDefinitionFromSource : (( Decode.Value, Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port incrementalBuild : (( Decode.Value, Decode.Value, Decode.Value, Distribution ) -> msg) -> Sub msg


port incrementalBuildResult : Encode.Value -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, Decode.Value, List SourceFile )
    | IncrementalBuild ( Decode.Value, Decode.Value, Decode.Value, Distribution )


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

        IncrementalBuild ( optionsJson, packageInfoJson, fileChangesJson, distribution ) ->
            let
                fileChangesResult : Result Decode.Error FileChanges
                fileChangesResult =
                    Decode.decodeValue FileChangesCodec.decodeFileChanges fileChangesJson

                inputResult : Result Decode.Error ( Frontend.Options, PackageInfo )
                inputResult =
                    Result.map2 Tuple.pair
                        (Decode.decodeValue FrontendCodec.decodeOptions optionsJson)
                        (Decode.decodeValue FrontendCodec.decodePackageInfo packageInfoJson)

                repoFromDistribution : Result Repo.Errors Repo
                repoFromDistribution =
                    Repo.fromDistribution distribution

                result : ( (), Cmd msg )
                result =
                    case repoFromDistribution of
                        Ok repo ->
                            case fileChangesResult of
                                Ok fileChanges ->
                                    ( model
                                    , Repo.applyFileChanges fileChanges repo
                                        |> Result.map Repo.toDistribution
                                        |> Result.mapError
                                            (List.map
                                                (\error ->
                                                    case error of
                                                        _ ->
                                                            Compiler.ErrorsInSourceFile "" []
                                                )
                                            )
                                        |> encodeResult (Encode.list CompilerCodec.encodeError) DistroCodec.encodeVersionedDistribution
                                        |> incrementalBuildResult
                                    )

                                Err error ->
                                    ( model
                                    , error
                                        |> Decode.errorToString
                                        |> jsonDecodeError
                                    )

                        Err errors ->
                            Debug.todo "Encode errors with repo error encoder"
            in
            case inputResult of
                Ok ( _, _ ) ->
                    result

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
