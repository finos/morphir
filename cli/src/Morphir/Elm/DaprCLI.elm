port module Morphir.Elm.DaprCLI exposing (main)

import Dict as Dict exposing (..)
import Elm.Syntax.Declaration as ElmSyn exposing (Declaration)
import Elm.Syntax.Exposing exposing (Exposing(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module exposing (Module(..))
import Elm.Syntax.Node exposing (Node)
import Elm.Syntax.Range as Range exposing (emptyRange)
import Elm.Writer as Writer exposing (..)
import Json.Decode as Decode
import Json.Encode as Encode
import Maybe.Extra as MaybeExtra exposing (..)
import Morphir.Elm.Backend.Codec.DecoderGen as DecoderGen exposing (typeDefToDecoder)
import Morphir.Elm.Backend.Codec.EncoderGen as EncoderGen exposing (typeDefToEncoder)
import Morphir.Elm.Backend.Dapr.StatefulApp as StatefulApp exposing (gen)
import Morphir.Elm.Backend.Utils as Utils exposing (..)
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, decodePackageInfo, encodeError)
import Morphir.IR.AccessControlled as AccessControlled exposing (..)
import Morphir.IR.Advanced.Module as Module exposing (..)
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.Advanced.Type as Type exposing (Definition(..), Type)
import Morphir.IR.Name as Name exposing (Name, toCamelCase)
import Morphir.IR.Path exposing (Path)


port packageDefinitionFromSource : (( Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefAndDaprCodeFromSrcResult : Encode.Value -> Cmd msg


port decodeError : String -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, List SourceFile )


type alias IrAndElmBackendResult =
    { packageDef : Package.Definition ()
    , elmBackendResult : String
    }


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
                        packageDefResult : Result Frontend.Errors (Package.Definition ())
                        packageDefResult =
                            Frontend.packageDefinitionFromSource packageInfo sourceFiles
                                |> Result.map Package.eraseDefinitionExtra

                        result =
                            packageDefResult
                                |> Result.map (\pd -> IrAndElmBackendResult pd (daprSource pd))
                    in
                    ( model, result |> encodeResult (Encode.list encodeError) (Package.encodeDefinition (\_ -> Encode.null)) |> packageDefAndDaprCodeFromSrcResult )

                Err errorMessage ->
                    ( model, errorMessage |> Decode.errorToString |> decodeError )


type alias AppArgs extra =
    { appPath : Path
    , appType : Type extra
    }


type alias StatefulAppArgs extra =
    { app : AppArgs extra
    , innerTypes : List ( Name, AccessControlled (Type.Definition ()) )
    }


daprSource : Package.Definition () -> String
daprSource packageDef =
    let
        appFiles : List File
        appFiles =
            packageDef.modules
                |> Dict.toList
                |> List.map (\( path, modDef ) -> createStatefulAppArgs path modDef)
                |> List.concat
                |> List.map (\statefulAppArgs -> StatefulApp.gen statefulAppArgs.app.appPath (Name.fromString "app") statefulAppArgs.app.appType statefulAppArgs.innerTypes)
                |> List.map MaybeExtra.toList
                |> List.concat

        createStatefulAppArgs : Path -> AccessControlled (Module.Definition extra) -> List (StatefulAppArgs extra)
        createStatefulAppArgs path acsCtrlModDef =
            let
                maybeApp : Maybe (AppArgs extra)
                maybeApp =
                    case acsCtrlModDef.access of
                        Public ->
                            case acsCtrlModDef.value of
                                { types, values } ->
                                    case Dict.get (Name.fromString "app") types of
                                        Just acsCtrlTypeDef ->
                                            case acsCtrlTypeDef.access of
                                                Public ->
                                                    case acsCtrlTypeDef.value of
                                                        TypeAliasDefinition _ tpe ->
                                                            { appPath = path
                                                            , appType = tpe
                                                            }
                                                                |> Just

                                                        _ ->
                                                            Nothing

                                                _ ->
                                                    Nothing

                                        _ ->
                                            Nothing

                        _ ->
                            Nothing

                innerTypes : List ( Name, AccessControlled (Type.Definition ()) )
                innerTypes =
                    case acsCtrlModDef.access of
                        Public ->
                            case acsCtrlModDef.value of
                                { types, values } ->
                                    Dict.remove (Name.fromString "app") types
                                        |> Dict.map (\_ acsCtrlTypeDef -> AccessControlled.map Type.eraseExtra acsCtrlTypeDef)
                                        |> Dict.toList

                        Private ->
                            []
            in
            Maybe.map
                (\app -> { app = app, innerTypes = innerTypes })
                maybeApp
                |> MaybeExtra.toList
    in
    appFiles
        |> List.map Writer.writeFile
        |> List.map Writer.write
        |> List.intersperse "\n"
        |> String.concat


elmBackendResult : Package.Definition () -> String
elmBackendResult packageDef =
    let
        codecDecls : List (Node ElmSyn.Declaration)
        codecDecls =
            packageDef.modules
                |> Dict.values
                |> List.map (mapPublic .types)
                |> List.map (Maybe.map (Dict.map codecs))
                |> MaybeExtra.values
                |> List.map Dict.values
                |> List.concat
                >> List.concat

        modDef : Node Module
        modDef =
            NormalModule
                { moduleName = [ "Example" ] |> Utils.emptyRangeNode
                , exposingList = All Range.emptyRange |> Utils.emptyRangeNode
                }
                |> Utils.emptyRangeNode

        file : File
        file =
            { moduleDefinition = modDef
            , imports = []
            , declarations = codecDecls
            , comments = []
            }
    in
    file
        |> Writer.writeFile
        |> Writer.write


codecs : Name -> AccessControlled (Type.Definition ()) -> List (Node ElmSyn.Declaration)
codecs typeName acsCtrlTypeDef =
    [ EncoderGen.typeDefToEncoder typeName acsCtrlTypeDef |> Utils.emptyRangeNode
    , DecoderGen.typeDefToDecoder typeName acsCtrlTypeDef |> Utils.emptyRangeNode
    ]


mapPublic : (a -> b) -> AccessControlled a -> Maybe b
mapPublic f acsCtrl =
    case acsCtrl.access of
        Public ->
            Just <| f acsCtrl.value

        _ ->
            Nothing


encodeResult : (Frontend.Errors -> Encode.Value) -> (Package.Definition () -> Encode.Value) -> Result Frontend.Errors IrAndElmBackendResult -> Encode.Value
encodeResult encodeError encodeValue result =
    case result of
        Ok a ->
            Encode.list identity
                [ Encode.null
                , Encode.object
                    [ ( "packageDef", encodeValue a.packageDef )
                    , ( "elmBackendResult", Encode.string a.elmBackendResult )
                    ]
                ]

        Err e ->
            Encode.list identity
                [ encodeError e
                , Encode.null
                ]
