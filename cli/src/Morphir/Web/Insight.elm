port module Morphir.Web.Insight exposing (Model(..), Msg(..), init, main, receiveFunctionArguments, receiveFunctionName, subscriptions, update, view)

import Browser
import Dict exposing (Dict)
import Element
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder, string)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.QName as QName exposing (QName(..))
import Morphir.IR.Value exposing (Value)
import Morphir.IR.Value.Codec as ValueCodec
import Morphir.Visual.Components.VisualizationState exposing (VisualizationState)
import Morphir.Visual.ViewValue as ViewValue



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
    | FunctionsSet VisualizationState
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


port receiveFunctionName : (String -> msg) -> Sub msg


port receiveFunctionArguments : (Decode.Value -> msg) -> Sub msg



-- UPDATE


type Msg
    = FunctionNameReceived String
    | FunctionArgumentsReceived Decode.Value
    | ExpandReference FQName Bool


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        getDistribution : Maybe Distribution
        getDistribution =
            case model of
                IRLoaded distribution ->
                    Just distribution

                FunctionsSet visualizationState ->
                    Just visualizationState.distribution

                _ ->
                    Nothing
    in
    case msg of
        FunctionNameReceived qNameString ->
            case qNameString |> QName.fromString of
                Just qName ->
                    getDistribution
                        |> Maybe.andThen
                            (\distribution ->
                                distribution
                                    |> Distribution.lookupValueDefinition qName
                                    |> Maybe.map
                                        (\funDef ->
                                            FunctionsSet
                                                { distribution = distribution
                                                , selectedFunction = qName
                                                , functionDefinition = funDef
                                                , functionArguments = []
                                                , expandedFunctions = Dict.empty
                                                }
                                        )
                            )
                        |> Maybe.map (\m -> ( m, Cmd.none ))
                        |> Maybe.withDefault ( Failed "Invalid State in receiving function name", Cmd.none )

                Nothing ->
                    ( Failed "Received function name is not found", Cmd.none )

        FunctionArgumentsReceived jsonList ->
            let
                jsonDecoder =
                    Decode.list (ValueCodec.decodeValue (Decode.succeed ()) (Decode.succeed ()))
            in
            case jsonList |> Decode.decodeValue jsonDecoder of
                Ok updatedArgValues ->
                    case model of
                        FunctionsSet visualizationState ->
                            ( FunctionsSet { visualizationState | functionArguments = updatedArgValues }
                            , Cmd.none
                            )

                        _ ->
                            ( Failed "Invalid State", Cmd.none )

                Err _ ->
                    ( Failed "Received function arguments cannot be decoded", Cmd.none )

        ExpandReference (( packageName, moduleName, localName ) as fqName) bool ->
            case model of
                FunctionsSet visualizationState ->
                    if visualizationState.expandedFunctions |> Dict.member fqName then
                        case bool of
                            True ->
                                ( FunctionsSet { visualizationState | expandedFunctions = visualizationState.expandedFunctions |> Dict.remove fqName }, Cmd.none )

                            False ->
                                ( model, Cmd.none )

                    else
                        ( FunctionsSet
                            { visualizationState
                                | expandedFunctions =
                                    Distribution.lookupValueDefinition (QName moduleName localName) visualizationState.distribution
                                        |> Maybe.map (\valueDef -> visualizationState.expandedFunctions |> Dict.insert fqName valueDef)
                                        |> Maybe.withDefault visualizationState.expandedFunctions
                            }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch [ receiveFunctionArguments FunctionArgumentsReceived, receiveFunctionName FunctionNameReceived ]



-- VIEW


view : Model -> Html Msg
view model =
    case model of
        IRLoaded _ ->
            Html.div [] [ Html.text "IR Loaded Successfully" ]

        Failed string ->
            Html.div [] [ Html.text string ]

        FunctionsSet visualizationState ->
            let
                validArgValues : Dict Name (Value () ())
                validArgValues =
                    List.map2
                        (\( argName, _, _ ) argValue ->
                            ( argName, argValue )
                        )
                        visualizationState.functionDefinition.inputTypes
                        visualizationState.functionArguments
                        |> Dict.fromList
            in
            ViewValue.viewDefinition visualizationState.distribution visualizationState.functionDefinition validArgValues ExpandReference visualizationState.expandedFunctions
                |> Element.layout []
