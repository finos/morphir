port module Morphir.Elm.CodecsCLI exposing (..)

import Dict as Dict exposing (..)
import Elm.Syntax.Declaration as S exposing (..)
import Elm.Syntax.Exposing exposing (..)
import Elm.Syntax.File exposing (..)
import Elm.Syntax.Module exposing (..)
import Elm.Syntax.Node exposing (..)
import Elm.Syntax.Range as Range exposing (..)
import Elm.Writer exposing (..)
import Json.Decode as Decode exposing (..)
import Morphir.Elm.Backend.Codec.DecoderGen exposing (..)
import Morphir.Elm.Backend.Codec.EncoderGen exposing (..)
import Morphir.Elm.Backend.Codec.Utils as Utils exposing (..)
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
    ( model, genCodecsFile sourceFiles |> elmEncoderBackend )


subscriptions : Model -> Sub Msg
subscriptions _ =
    elmFrontEnd PackageDefinitionFromSource


port elmEncoderBackend : String -> Cmd msg


port elmFrontEnd : (( Decode.Value, List SourceFile ) -> msg) -> Sub msg


genCodecsFile : List SourceFile -> String
genCodecsFile sources =
    let
        file : File
        file =
            { moduleDefinition =
                Utils.emptyRangeNode <|
                    NormalModule
                        { moduleName = Utils.emptyRangeNode [ "AEncoders" ]
                        , exposingList = Utils.emptyRangeNode (All emptyRange)
                        }
            , imports = []
            , declarations =
                case codecDeclarations sources of
                    Ok decls ->
                        decls

                    Err _ ->
                        []
            , comments = []
            }
    in
    writeFile file |> write


codecDeclarations : List SourceFile -> Result Errors (List (Node S.Declaration))
codecDeclarations sourceFiles =
    packageDefinitionFromSource emptyPackageInfo sourceFiles
        |> Result.map .modules
        |> Result.map Dict.values
        |> Result.map (List.map getCodecsFromModuleDef)
        |> Result.map List.concat


getCodecsFromModuleDef : AccessControlled (Advanced.Definition SourceLocation) -> List (Node S.Declaration)
getCodecsFromModuleDef accessCtrlModuleDef =
    case accessCtrlModuleDef of
        Public { types, values } ->
            let
                typesToDecl f tpes =
                    tpes
                        |> List.map
                            (\typeNameAndDef ->
                                f emptySourceLocation
                                    (Tuple.first typeNameAndDef)
                                    (Tuple.second typeNameAndDef)
                            )
                        |> List.map (Node Range.emptyRange)
            in
            (Dict.toList types |> typesToDecl typeDefToEncoder)
                ++ (Dict.toList types |> typesToDecl typeDefToDecoder)

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
    , exposedModules = Set.fromList [ [ [ "a" ] ] ]
    }
