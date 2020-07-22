port module Morphir.Elm.CLI exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, decodePackageInfo, encodeError)
import Morphir.File.FileMap.Codec exposing (encodeFileMap)
import Morphir.IR.Package as Package
import Morphir.IR.Package.Codec as PackageCodec
import Morphir.Scala.Backend as Backend
import Morphir.Scala.Backend.Codec exposing (decodeOptions)


port packageDefinitionFromSource : (( Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port decodeError : String -> Cmd msg


port generate : (( Decode.Value, Decode.Value ) -> msg) -> Sub msg


port generateResult : Encode.Value -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, List SourceFile )
    | Generate ( Decode.Value, Decode.Value )


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
        PackageDefinitionFromSource ( packageInfoJson, sourceFiles ) ->
            case Decode.decodeValue decodePackageInfo packageInfoJson of
                Ok packageInfo ->
                    let
                        result =
                            Frontend.packageDefinitionFromSource packageInfo sourceFiles
                                |> Result.map Package.eraseDefinitionAttributes
                    in
                    ( model, result |> encodeResult (Encode.list encodeError) (PackageCodec.encodeDefinition (\_ -> Encode.object [])) |> packageDefinitionFromSourceResult )

                Err errorMessage ->
                    ( model, errorMessage |> Decode.errorToString |> decodeError )

        Generate ( optionsJson, packageDefJson ) ->
            let
                optionsResult =
                    Decode.decodeValue decodeOptions optionsJson

                packageDefResult =
                    Decode.decodeValue (PackageCodec.decodeDefinition (Decode.succeed ())) packageDefJson
            in
            case Result.map2 Tuple.pair optionsResult packageDefResult of
                Ok ( options, packageDef ) ->
                    let
                        fileMap =
                            Backend.mapPackageDefinition options packageDef
                    in
                    ( model, fileMap |> Ok |> encodeResult Encode.string encodeFileMap |> generateResult )

                Err errorMessage ->
                    ( model, errorMessage |> Decode.errorToString |> decodeError )


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch
        [ packageDefinitionFromSource PackageDefinitionFromSource
        , generate Generate
        ]


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
