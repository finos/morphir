port module Morphir.Web.Insight exposing (..)

import Browser
import Dict
import Element
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder, string)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.QName as QName exposing (QName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.IR.Value.Codec as ValueCodec
import Morphir.Visual.ViewValue



-- MAIN


main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODEL


type Model
    = IRLoaded Distribution
    | FunctionNameSet Distribution QName (Value.Definition () (Type ()))
    | FunctionArgumentsSet Distribution QName (Value.Definition () (Type ())) (List (Value () ()))
    | Failed String


init : Decode.Value -> ( Model, Cmd Msg )
init distributionJson =
    let
        model =
            case distributionJson |> Decode.decodeValue DistributionCodec.decodeDistribution of
                Ok distribution ->
                    IRLoaded distribution

                Err error ->
                    Failed "Wrong IR"
    in
    ( model, Cmd.none )



-- PORTS
--port sendErrorReport : String -> Cmd msg


port receiveFunctionName : (String -> Msg) -> Sub Msg


port receiveFunctionArguments : (Decode.Value -> Msg) -> Sub Msg



-- UPDATE


type Msg
    = FunctionArgumentsReceived Decode.Value
    | FunctionNameReceived String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        getDistribution : Maybe Distribution
        getDistribution =
            case model of
                IRLoaded distribution ->
                    Just distribution

                FunctionNameSet distribution _ _ ->
                    Just distribution

                _ ->
                    Nothing
    in
    case msg of
        FunctionArgumentsReceived jsonList ->
            let
                jsonDecoder =
                    Decode.list (ValueCodec.decodeValue (Decode.succeed ()) (Decode.succeed ()))
            in
            case jsonList |> Decode.decodeValue jsonDecoder of
                Ok updatedArgValues ->
                    case model of
                        FunctionNameSet distribution qName valueDef ->
                            ( FunctionArgumentsSet distribution qName valueDef updatedArgValues, Cmd.none )

                        FunctionArgumentsSet distribution qName valueDef _ ->
                            ( FunctionArgumentsSet distribution qName valueDef updatedArgValues, Cmd.none )

                        _ ->
                            ( Failed "Invalid State", Cmd.none )

                Err _ ->
                    ( Failed "Received Arguments Cannot Decode", Cmd.none )

        FunctionNameReceived qNameString ->
            case qNameString |> QName.fromString of
                Just qName ->
                    getDistribution
                        |> Maybe.andThen
                            (\distribution ->
                                distribution
                                    |> Distribution.lookupValueDefinition qName
                                    |> Maybe.map (\valueDef -> FunctionNameSet distribution qName valueDef)
                            )
                        |> Maybe.map (\m -> ( m, Cmd.none ))
                        |> Maybe.withDefault ( Failed "Invalid State", Cmd.none )

                Nothing ->
                    ( Failed "Function Name Received is Not correct", Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch [ receiveFunctionArguments FunctionArgumentsReceived, receiveFunctionName FunctionNameReceived ]



-- VIEW


view : Model -> Html Msg
view model =
    case model of
        IRLoaded distribution ->
            Html.div [] []

        Failed string ->
            Html.div [] [ Html.text string ]

        FunctionNameSet distribution qName valueDef ->
            Morphir.Visual.ViewValue.view valueDef.body |> Element.layout []

        FunctionArgumentsSet distribution qName valueDef argValues ->
            List.map2
                (\( argName, _, _ ) argValue ->
                    ( argName, argValue )
                )
                valueDef.inputTypes
                argValues
                |> Dict.fromList
                |> Morphir.Visual.ViewValue.viewWithData distribution valueDef
                |> Element.layout []
