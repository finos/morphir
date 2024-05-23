module Morphir.Visual.Components.TypeInferenceView exposing (..)

import Dict
import Element exposing (Element, column, el, none, padding, rgb, row, shrink, spacing, table, text)
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Name as Name
import Morphir.Type.Constraint exposing (Constraint(..))
import Morphir.Type.ConstraintSet as ConstraintSet exposing (ConstraintSet)
import Morphir.Type.Infer as Infer
import Morphir.Type.MetaType exposing (MetaType(..))
import Morphir.Type.Solve as Solve exposing (SolutionMap)


viewConstraints : ConstraintSet -> Element msg
viewConstraints constraints =
    column [ spacing 10 ]
        (constraints
            |> ConstraintSet.toList
            |> List.map
                (\constraint ->
                    case constraint of
                        Equality _ metaType1 metaType2 ->
                            el
                                [ padding 5
                                , Border.rounded 5
                                , Background.color (rgb 0.8 0.9 0.9)
                                ]
                                (column [ spacing 5 ]
                                    [ viewMetaType metaType1
                                    , viewMetaType metaType2
                                    ]
                                )

                        Class _ metaType cls ->
                            column []
                                [ viewMetaType metaType
                                , row [] [ text "is a", text (Debug.toString cls) ]
                                ]
                )
        )


viewMetaType : MetaType -> Element msg
viewMetaType metaType =
    case metaType of
        MetaVar variable ->
            text (String.fromInt variable)

        MetaRef _ ( packageName, moduleName, localName ) args maybeMetaType ->
            row [ spacing 10 ]
                [ text (Name.toTitleCase localName)
                , args |> List.map viewMetaType |> row [ spacing 10 ]
                , case maybeMetaType of
                    Just alias ->
                        row [ spacing 10 ] [ text "as", viewMetaType alias ]

                    Nothing ->
                        none
                ]

        MetaTuple _ metaTypes ->
            row [ spacing 10 ]
                [ text "("
                , metaTypes |> List.map viewMetaType |> List.intersperse (text ",") |> row [ spacing 10 ]
                , text ")"
                ]

        MetaRecord _ var isOpen fields ->
            row []
                [ text "{ "
                , text (String.fromInt var)
                , if isOpen then
                    text " = "

                  else
                    text " | "
                , fields
                    |> Dict.toList
                    |> List.map (\( n, t ) -> row [] [ text (Name.toCamelCase n), text " : ", viewMetaType t ])
                    |> List.intersperse (text ", ")
                    |> row []
                , text " }"
                ]

        MetaFun _ metaType1 metaType2 ->
            row [] [ viewMetaType metaType1, text " -> ", viewMetaType metaType2 ]

        MetaUnit ->
            text "()"


viewSolution : SolutionMap -> Element msg
viewSolution solutionMap =
    table [ spacing 10 ]
        { data =
            solutionMap
                |> Solve.toList
        , columns =
            [ { header = none
              , width = shrink
              , view =
                    \( variable, _ ) ->
                        text (String.fromInt variable)
              }
            , { header = none
              , width = shrink
              , view =
                    \_ ->
                        text "="
              }
            , { header = none
              , width = shrink
              , view =
                    \( _, metaType ) ->
                        viewMetaType metaType
              }
            ]
        }


viewSolveSteps : Int -> Distribution -> SolutionMap -> ConstraintSet -> List (Element msg)
viewSolveSteps depth ir solutionMap constraintSet =
    let
        thisStep : Element msg
        thisStep =
            column [ spacing 20 ]
                [ text "Constraints"
                , viewConstraints constraintSet
                , text "Solutions"
                , viewSolution solutionMap
                ]
    in
    case Infer.solveStep ir solutionMap constraintSet of
        Ok (Just ( newConstraints, mergedSolutions )) ->
            if depth > 50 then
                [ thisStep ]

            else
                thisStep :: viewSolveSteps (depth + 1) ir mergedSolutions newConstraints

        Ok Nothing ->
            [ thisStep ]

        Err error ->
            [ text (Debug.toString error) ]
