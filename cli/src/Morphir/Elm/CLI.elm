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

import Dict
import Json.Decode as Decode exposing (field, string)
import Json.Encode as Encode
import Morphir.Elm.Frontend as Frontend exposing (PackageInfo, SourceFile, SourceLocation)
import Morphir.Elm.Frontend.Codec as FrontendCodec exposing (decodePackageInfo)
import Morphir.Elm.Target exposing (decodeOptions, mapDistribution)
import Morphir.File.FileMap.Codec exposing (encodeFileMap)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.Package as Package
import Morphir.IR.Type exposing (Type)
import Morphir.Type.Infer as Infer
import Morphir.Type.Infer.Codec exposing (encodeTypeError, encodeValueTypeError)
import Morphir.Type.MetaTypeMapping as MetaTypeMapping


port packageDefinitionFromSource : (( Decode.Value, List SourceFile ) -> msg) -> Sub msg


port packageDefinitionFromSourceResult : Encode.Value -> Cmd msg


port decodeError : String -> Cmd msg


port generate : (( Decode.Value, Decode.Value ) -> msg) -> Sub msg


port generateResult : Encode.Value -> Cmd msg


type Msg
    = PackageDefinitionFromSource ( Decode.Value, List SourceFile )
    | Generate ( Decode.Value, Decode.Value )


type Error
    = FrontendError Frontend.Errors
    | TypeError (List Infer.ValueTypeError)


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
                        frontendResult : Result Error (Package.Definition Frontend.SourceLocation Frontend.SourceLocation)
                        frontendResult =
                            Frontend.packageDefinitionFromSource packageInfo Dict.empty sourceFiles
                                |> Result.mapError FrontendError

                        typedResult : Result Error (Package.Definition () ( Frontend.SourceLocation, Type () ))
                        typedResult =
                            frontendResult
                                |> Result.andThen
                                    (\packageDef ->
                                        let
                                            thisPackageSpec : Package.Specification ()
                                            thisPackageSpec =
                                                packageDef
                                                    |> Package.definitionToSpecification
                                                    |> Package.mapSpecificationAttributes (\_ -> ()) (\_ -> ())

                                            references : MetaTypeMapping.References
                                            references =
                                                Frontend.defaultDependencies
                                                    |> Dict.insert packageInfo.name thisPackageSpec
                                        in
                                        packageDef
                                            |> Package.mapDefinitionAttributes (\_ -> ()) identity
                                            |> Infer.inferPackageDefinition references
                                            |> Result.mapError TypeError
                                    )
                    in
                    ( model
                    , typedResult
                        |> Result.map (Package.mapDefinitionAttributes identity (\( _, tpe ) -> tpe))
                        |> Result.map (Distribution.Library packageInfo.name Dict.empty)
                        |> encodeResult encodeError DistributionCodec.encodeDistribution
                        |> packageDefinitionFromSourceResult
                    )

                Err errorMessage ->
                    ( model
                    , errorMessage
                        |> Decode.errorToString
                        |> decodeError
                    )

        Generate ( optionsJson, packageDistJson ) ->
            let
                targetOption =
                    Decode.decodeValue (field "target" string) optionsJson

                optionsResult =
                    Decode.decodeValue (decodeOptions targetOption) optionsJson

                packageDistroResult =
                    Decode.decodeValue DistributionCodec.decodeDistribution packageDistJson
            in
            case Result.map2 Tuple.pair optionsResult packageDistroResult of
                Ok ( options, packageDist ) ->
                    let
                        enrichedDistro =
                            case packageDist of
                                Library packageName dependencies packageDef ->
                                    Library packageName (Dict.union Frontend.defaultDependencies dependencies) packageDef

                        fileMap =
                            mapDistribution options enrichedDistro
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


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        FrontendError frontendErrors ->
            Encode.list FrontendCodec.encodeError frontendErrors

        TypeError typeError ->
            Encode.list encodeValueTypeError typeError
