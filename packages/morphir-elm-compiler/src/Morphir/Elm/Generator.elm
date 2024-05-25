port module Morphir.Elm.Generator exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)
import Morphir.Elm.Generator.API as Generator
import Morphir.Elm.Generator.ValueGenerators as ValueGenerator
import Morphir.IR.Distribution as IR exposing (Distribution(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.FormatVersion.Codec as DistroCodec
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec as DataCodec
import Morphir.IR.Value exposing (RawValue)
import Morphir.SDK.ResultList as ResultList
import Set exposing (Set)


port decodeFailed : String -> Cmd msg


port generate : (Value -> msg) -> Sub msg


port generated : Value -> Cmd msg


port generationFailed : String -> Cmd msg


type Msg
    = Generate Value


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


type alias TestData =
    ( Int, List RawValue )


type alias Input =
    { distro : Distribution
    , targets : Set FQName
    , size : Int
    , seed : Int
    }


update : Msg -> () -> ( (), Cmd Msg )
update msg () =
    case msg of
        Generate inputJson ->
            let
                inputResult : Result Decode.Error Input
                inputResult =
                    inputJson
                        |> Decode.decodeValue
                            (Decode.map4 Input
                                (Decode.field "morphirIrJson" DistroCodec.decodeVersionedDistribution)
                                (Decode.field "targets"
                                    (Decode.map Set.fromList <|
                                        Decode.list
                                            (Decode.map
                                                (\fqnString ->
                                                    FQName.fromString fqnString ":"
                                                )
                                                Decode.string
                                            )
                                    )
                                )
                                (Decode.field "size" Decode.int)
                                (Decode.field "seed" Decode.int)
                            )
            in
            case inputResult of
                Ok { distro, size, targets, seed } ->
                    if Set.isEmpty targets then
                        ( (), generationFailed "No targets provided" )

                    else
                        let
                            ir =
                                distro

                            fqnByTpeSpecsResult =
                                targets
                                    |> Set.toList
                                    |> List.map
                                        (\fqn ->
                                            IR.lookupTypeSpecification fqn ir
                                                |> Maybe.map (Tuple.pair fqn)
                                                |> Result.fromMaybe
                                                    ("FQName not found: "
                                                        ++ FQName.toString fqn
                                                    )
                                        )
                                    |> ResultList.keepFirstError

                            generatorsResult : Result String (Dict.Dict FQName ( Type (), Generator.Generator RawValue ))
                            generatorsResult =
                                fqnByTpeSpecsResult
                                    |> Result.andThen
                                        (\fqnByTpeSpecs ->
                                            fqnByTpeSpecs
                                                |> List.map
                                                    (\( fqn, tpeSpec ) ->
                                                        case tpeSpec of
                                                            Type.TypeAliasSpecification args tpe ->
                                                                ValueGenerator.fromType ir tpe
                                                                    |> Result.map (Tuple.pair tpe)
                                                                    |> Result.map (Tuple.pair fqn)

                                                            Type.OpaqueTypeSpecification lists ->
                                                                Debug.todo "Implement this"

                                                            Type.CustomTypeSpecification lists constructors ->
                                                                Debug.todo "Implement this"

                                                            Type.DerivedTypeSpecification lists derivedTypeSpecificationDetails ->
                                                                Debug.todo "Implement this"
                                                    )
                                                |> ResultList.keepFirstError
                                                |> Result.map Dict.fromList
                                        )

                            generatedValues : Result String (Dict.Dict FQName ( Type (), List RawValue ))
                            generatedValues =
                                let
                                    genSeed =
                                        Generator.seed seed
                                in
                                generatorsResult
                                    |> Result.map
                                        (Dict.map
                                            (\k ( tpe, generator ) ->
                                                ( tpe, Generator.nextN size genSeed generator )
                                            )
                                        )
                        in
                        case generatedValues of
                            Ok valuesByFQName ->
                                let
                                    getCodec tpe =
                                        DataCodec.encodeData ir tpe
                                in
                                ( ()
                                , valuesByFQName
                                    |> Encode.dict FQName.toString
                                        (\( tpe, values ) ->
                                            let
                                                codecResult =
                                                    getCodec tpe
                                            in
                                            codecResult
                                                |> Result.map
                                                    (\codec ->
                                                        values
                                                            |> Encode.list
                                                                (\value ->
                                                                    codec value
                                                                        |> Result.withDefault (Encode.string "Encoder failed")
                                                                )
                                                    )
                                                |> Result.withDefault (Encode.object [])
                                        )
                                    |> generated
                                )

                            Err error ->
                                ( (), generationFailed error )

                Err error ->
                    ( ()
                    , Decode.errorToString error
                        |> decodeFailed
                    )


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.batch [ generate Generate ]
