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


port module Morphir.Elm.DaprCLI exposing (main)

import Dict as Dict exposing (..)
import Elm.Syntax.Declaration as ElmSyn exposing (Declaration)
import Elm.Syntax.Exposing exposing (Exposing(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module exposing (Module(..))
import Elm.Syntax.Node exposing (Node)
import Elm.Syntax.Range as Range
import Elm.Writer as Writer exposing (..)
import Json.Decode as Decode
import Json.Encode as Encode
import Maybe.Extra as MaybeExtra exposing (..)
import Morphir.Elm.Backend.Codec.DecoderGen as DecoderGen
import Morphir.Elm.Backend.Codec.EncoderGen as EncoderGen
import Morphir.Elm.Backend.Dapr.StatefulApp as StatefulApp
import Morphir.Elm.Backend.Utils as Utils exposing (..)
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile)
import Morphir.Elm.Frontend.Codec exposing (decodePackageInfo, encodeError)
import Morphir.IR.AccessControlled as AccessControlled exposing (..)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (..)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Package.Codec as PackageCodec
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Definition(..), Type)


port packageDefinitionFromSource : (( Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefAndDaprCodeFromSrcResult : Encode.Value -> Cmd msg


port decodeError : String -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, List SourceFile )


type alias IrAndElmBackendResult =
    { packageDef : Package.Definition () ()
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
                Ok pkgInfo ->
                    let
                        packageDefResult : Result Frontend.Errors (Package.Definition () ())
                        packageDefResult =
                            Frontend.packageDefinitionFromSource (Frontend.Options False) pkgInfo Dict.empty sourceFiles
                                |> Result.map Package.eraseDefinitionAttributes

                        result =
                            packageDefResult
                                |> Result.map (\pkgDef -> IrAndElmBackendResult pkgDef (daprSource pkgInfo.name pkgDef))
                    in
                    ( model, result |> encodeResult (Encode.list encodeError) (PackageCodec.encodeDefinition (\_ -> Encode.null) (\_ -> Encode.null)) |> packageDefAndDaprCodeFromSrcResult )

                Err errorMessage ->
                    ( model, errorMessage |> Decode.errorToString |> decodeError )


type alias AppArgs extra =
    { appPath : Path
    , appType : Type extra
    }


type alias StatefulAppArgs extra =
    { app : AppArgs extra
    , innerTypes : List ( Name, AccessControlled (Documented (Type.Definition ())) )
    }


daprSource : Path -> Package.Definition () () -> String
daprSource pkgPath pkgDef =
    let
        appFiles : List File
        appFiles =
            pkgDef.modules
                |> Dict.toList
                |> List.map (\( modPath, modDef ) -> createStatefulAppArgs modPath modDef)
                |> List.concat
                |> List.map (\statefulAppArgs -> StatefulApp.gen statefulAppArgs.app.appPath (Name.fromString "app") statefulAppArgs.app.appType statefulAppArgs.innerTypes)
                |> List.map MaybeExtra.toList
                |> List.concat

        createStatefulAppArgs : Path -> AccessControlled (Module.Definition extra extra) -> List (StatefulAppArgs extra)
        createStatefulAppArgs modPath acsCtrlModDef =
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
                                                    case acsCtrlTypeDef.value.value of
                                                        TypeAliasDefinition _ tpe ->
                                                            { appPath = pkgPath ++ modPath
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

                innerTypes : List ( Name, AccessControlled (Documented (Type.Definition ())) )
                innerTypes =
                    case acsCtrlModDef.access of
                        Public ->
                            case acsCtrlModDef.value of
                                { types, values } ->
                                    Dict.remove (Name.fromString "app") types
                                        |> Dict.map (\_ acsCtrlTypeDef -> acsCtrlTypeDef |> AccessControlled.map (Documented.map Type.eraseAttributes))
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


elmBackendResult : Package.Definition () () -> String
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


codecs : Name -> AccessControlled (Documented (Type.Definition ())) -> List (Node ElmSyn.Declaration)
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


encodeResult : (Frontend.Errors -> Encode.Value) -> (Package.Definition () () -> Encode.Value) -> Result Frontend.Errors IrAndElmBackendResult -> Encode.Value
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
