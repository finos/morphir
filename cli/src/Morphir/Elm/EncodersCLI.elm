port module Morphir.Elm.EncodersCLI exposing (..)

import Dict as Dict exposing (..)
import Elm.Syntax.Declaration as S exposing (..)
import Elm.Syntax.Exposing exposing (..)
import Elm.Syntax.File exposing (..)
import Elm.Syntax.Module exposing (..)
import Elm.Syntax.Node exposing (..)
import Elm.Syntax.Range exposing (..)
import Elm.Writer exposing (..)
import Json.Decode as Decode exposing (..)
import Morphir.Elm.Backend.Codec.Gen exposing (..)
import Morphir.Elm.Frontend exposing (..)
import Morphir.IR.AccessControlled exposing (..)
import Morphir.IR.Advanced.Module as Advanced exposing (..)
import Morphir.IR.Name exposing (..)
import Set exposing (..)


main =
    Platform.worker
        { init = init, update = update, subscriptions = subscriptions }


type Msg
    = PackageDefinitionFromSource ( Decode.Value, List SourceFile )


type alias Model =
    ()


init : () -> ( Model, Cmd Msg )
init _ =
    ( (), Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update (PackageDefinitionFromSource ( _, sourceFiles )) model =
    ( model, genEncodersFile sourceFiles |> elmEncoderBackend )


subscriptions : Model -> Sub Msg
subscriptions _ =
    elmFrontEnd PackageDefinitionFromSource


port elmEncoderBackend : String -> Cmd msg


port elmFrontEnd : (( Decode.Value, List SourceFile ) -> msg) -> Sub msg


genEncodersFile : List SourceFile -> String
genEncodersFile sources =
    let
        file =
            { moduleDefinition =
                emptyRangeNode <|
                    NormalModule
                        { moduleName = emptyRangeNode [ "AEncoders" ]
                        , exposingList = emptyRangeNode (All emptyRange)
                        }
            , imports = []
            , declarations =
                case encoderDeclarations sources of
                    Ok maybList ->
                        case maybList of
                            Just list ->
                                list

                            Nothing ->
                                []

                    Err _ ->
                        []
            , comments = []
            }
    in
    writeFile file |> write


encoderDeclarations : List SourceFile -> Result Errors (Maybe (List (Node S.Declaration)))
encoderDeclarations sourceFiles =
    packageDefinitionFromSource emptyPackageInfo sourceFiles
        |> Result.map .modules
        |> Result.map (Dict.get [ [ "a" ] ])
        |> Result.map (Maybe.map getEncodersFromModuleDef)


getEncodersFromModuleDef : AccessControlled (Advanced.Definition SourceLocation) -> List (Node S.Declaration)
getEncodersFromModuleDef accessCtrlModuleDef =
    case accessCtrlModuleDef of
        Public { types, values } ->
            Dict.toList types
                |> List.map
                    (\typeNameAndDef ->
                        typeDefToEncoder emptySourceLocation
                            (Tuple.first typeNameAndDef)
                            (Tuple.second typeNameAndDef)
                    )
                |> List.map (Node emptyRange)

        _ ->
            []


emptySourceLocation : SourceLocation
emptySourceLocation =
    { source =
        { path = ""
        , content = ""
        }
    , range =
        { start =
            { row = 0
            , column = 0
            }
        , end =
            { row = 0
            , column = 0
            }
        }
    }


emptyPackageInfo : PackageInfo
emptyPackageInfo =
    { name = []
    , exposedModules = Set.fromList [ [ fromString "a" ] ]
    }
