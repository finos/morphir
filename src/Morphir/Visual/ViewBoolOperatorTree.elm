module Morphir.Visual.ViewBoolOperatorTree exposing (..)

import Element exposing (Element)
import Morphir.IR.Value exposing (TypedValue)
import Morphir.Visual.BoolOperatorTree exposing (BoolOperatorTree(..))


view : (TypedValue -> Element msg) -> BoolOperatorTree -> Element msg
view viewValue boolOperatorTree =
    viewTreeNode viewValue Vertical boolOperatorTree


viewTreeNode : (TypedValue -> Element msg) -> LayoutDirection -> BoolOperatorTree -> Element msg
viewTreeNode viewValue direction boolOperatorTree =
    case boolOperatorTree of
        BoolOperatorBranch operator values ->
            -- TODO: add AND or OR separator between values base on the operator passed in
            let
                layout : List (Element msg) -> Element msg
                layout elems =
                    case direction of
                        Horizontal ->
                            Element.row [] elems

                        Vertical ->
                            Element.column [] elems
            in
            values
                |> List.map (viewTreeNode viewValue (flipLayoutDirection direction))
                |> layout

        BoolValueLeaf value ->
            viewValue value


type LayoutDirection
    = Horizontal
    | Vertical


flipLayoutDirection : LayoutDirection -> LayoutDirection
flipLayoutDirection direction =
    case direction of
        Horizontal ->
            Vertical

        Vertical ->
            Horizontal
