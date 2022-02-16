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
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Codec as FrontendCodec
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Package as Package exposing (PackageName)


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port jsonDecodeError : String -> Cmd msg


port incrementalBuild : (( Decode.Value, Decode.Value, List SourceFile, List IR ) -> msg) -> Sub msg


port incrementalBuildResult : ( Encode.Value, Encode.Value ) -> Cmd msg


type Msg
    = IncrementalBuild ( Decode.Value, Decode.Value, List SourceFile, List IR )


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
        IncrementalBuild ( optionsJson, packageInfoJson, sourceFiles, irJson ) ->
            let
                inputResult : Result Decode.Error ( Frontend.Options, PackageInfo )
                inputResult =
                    Result.map2 Tuple.pair
                        (Decode.decodeValue FrontendCodec.decodeOptions optionsJson)
                        (Decode.decodeValue FrontendCodec.decodePackageInfo packageInfoJson)

                -- (Decode.decodeValue FrontendCodec.decodePackageInfo packageInfoJson)
            in
            case inputResult of
                Ok ( opts, packageInfo ) ->
                    let
                        createEmptyRepo : Result (List Compiler.Error) (Package.Definition () () )
                        createEmptyRepo =
                            Repo.Empty


                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> jsonDecodeError
                    )


subscriptions : () -> Sub Msg
subscriptions _ =
    incrementalBuild IncrementalBuild


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
