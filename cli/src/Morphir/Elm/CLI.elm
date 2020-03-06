port module Morphir.Elm.CLI exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, decodePackageInfo, encodeError)
import Morphir.IR.Advanced.Package as Package


port packageDefinitionFromSource : (( Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port decodeError : String -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, List SourceFile )


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = \_ -> packageDefinitionFromSource PackageDefinitionFromSource
        }


update : Msg -> () -> ( (), Cmd Msg )
update msg model =
    case msg of
        PackageDefinitionFromSource ( packageInfoJson, sourceFiles ) ->
            case Decode.decodeValue decodePackageInfo packageInfoJson of
                Ok packageInfo ->
                    let
                        result =
                            Frontend.packageDefinitionFromSource packageInfo sourceFiles
                                |> Result.map Package.eraseDefinitionExtra
                    in
                    ( model, result |> encodeResult (Encode.list encodeError) (Package.encodeDefinition (\_ -> Encode.null)) |> packageDefinitionFromSourceResult )

                Err errorMessage ->
                    ( model, errorMessage |> Decode.errorToString |> decodeError )


encodeResult : (e -> Encode.Value) -> (a -> Encode.Value) -> Result e a -> Encode.Value
encodeResult encodeError encodeValue result =
    case result of
        Ok a ->
            Encode.list identity
                [ Encode.null
                , encodeValue a
                ]

        Err e ->
            Encode.list identity
                [ encodeError e
                , Encode.null
                ]
