port module Morphir.Elm.CLI2 exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Codec as FrontendCodec


port packageDefinitionFromSource : (( Decode.Value, Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port jsonDecodeError : String -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, Decode.Value, List SourceFile )


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


update : Msg -> () -> ( (), Cmd msg )
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
                        Ok ( opts, packageInfo ) ->
                                --create empty repo and send files incrementally
                        Err errorMessage ->
                                -- print out error message


subscriptions : () -> Sub Msg
subscriptions _ =
    packageDefinitionFromSource PackageDefinitionFromSource
