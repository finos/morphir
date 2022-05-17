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


port module Morphir.Elm.FrontendWorker exposing (main)

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Elm.Frontend2 exposing (ParseAndOrderError(..), ParseError, ParseResult(..), SourceFiles, parseAndOrderModules)
import Morphir.Elm.ModuleName exposing (ModuleName)
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)


port receiveNewSources : (Decode.Value -> msg) -> Sub msg


port sendInvalidMessageSentToPort : ( String, String ) -> Cmd msg


port sendMissingModules : Encode.Value -> Cmd msg


port sendOrderedModules : Encode.Value -> Cmd msg


port sendParseErrors : Encode.Value -> Cmd msg


port sendModuleDependencyCycles : Encode.Value -> Cmd msg


main : Platform.Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


type alias Flags =
    Decode.Value


type alias Model =
    { parsedModules : List ParsedModule
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        initModel : Model
        initModel =
            { parsedModules = []
            }
    in
    ( initModel, Cmd.none )


type Msg
    = NewSources SourceFiles
    | InvalidMessageSentToPort String Decode.Error


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InvalidMessageSentToPort portName error ->
            ( model, sendInvalidMessageSentToPort ( portName, Decode.errorToString error ) )

        NewSources sourceFiles ->
            case parseAndOrderModules sourceFiles (always False) model.parsedModules of
                Ok (MissingModules missingModules parsedModules) ->
                    ( { model | parsedModules = parsedModules }
                    , sendMissingModules (encodeMissingModules missingModules)
                    )

                Ok (OrderedModules orderedParsedModules) ->
                    ( { model | parsedModules = orderedParsedModules }
                    , sendOrderedModules (orderedParsedModules |> List.map ParsedModule.moduleName |> encodeMissingModules)
                    )

                Err (ParseErrors parseErrors) ->
                    ( model
                    , sendParseErrors (encodeParseErrors parseErrors)
                    )

                Err (ModuleDependencyCycles cycles) ->
                    ( model
                    , sendModuleDependencyCycles (encodeCycles cycles)
                    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ receiveNewSources (jsonPort "newSources" decodeSourceFiles NewSources)
        ]


decodeSourceFiles : Decode.Decoder SourceFiles
decodeSourceFiles =
    Decode.dict Decode.string


encodeMissingModules : List ModuleName -> Encode.Value
encodeMissingModules moduleNames =
    moduleNames
        |> List.map (String.join ".")
        |> Encode.list Encode.string


encodeParseErrors : Dict String (List ParseError) -> Encode.Value
encodeParseErrors parseErrors =
    Encode.dict identity
        (Encode.list
            (\parseError ->
                Encode.object
                    [ ( "problem", Encode.string parseError.problem )
                    , ( "location"
                      , Encode.list identity
                            [ Encode.int parseError.location.row
                            , Encode.int parseError.location.column
                            ]
                      )
                    ]
            )
        )
        parseErrors


encodeCycles : List (List ModuleName) -> Encode.Value
encodeCycles cycles =
    cycles
        |> List.map (List.map (String.join "."))
        |> Encode.list (Encode.list Encode.string)


jsonPort : String -> Decode.Decoder a -> (a -> Msg) -> Decode.Value -> Msg
jsonPort portName decoder toMessage jsonMessage =
    case Decode.decodeValue decoder jsonMessage of
        Ok decoded ->
            toMessage decoded

        Err error ->
            InvalidMessageSentToPort portName error
