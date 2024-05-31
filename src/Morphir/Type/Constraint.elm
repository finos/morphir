module Morphir.Type.Constraint exposing (..)

import Dict exposing (Dict)
import Morphir.Type.Class as Class exposing (Class)
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable)
import Set exposing (Set)


type Constraint
    = Equality (Set Variable) MetaType MetaType
    | Class (Set Variable) MetaType Class


equality : MetaType -> MetaType -> Constraint
equality metaType1 metaType2 =
    Equality (Set.union (MetaType.variables metaType1) (MetaType.variables metaType2))
        metaType1
        metaType2


class : MetaType -> Class -> Constraint
class metaType cls =
    Class (MetaType.variables metaType)
        metaType
        cls


variables : Constraint -> Set Variable
variables constraint =
    case constraint of
        Equality vars _ _ ->
            vars

        Class vars _ _ ->
            vars


equivalent : Constraint -> Constraint -> Bool
equivalent constraint1 constraint2 =
    if constraint1 == constraint2 then
        True

    else
        case ( constraint1, constraint2 ) of
            ( Equality _ a1 a2, Equality _ b1 b2 ) ->
                (a1 == b1 && a2 == b2) || (a1 == b2 && a2 == b1)

            _ ->
                False


substituteVariable : Variable -> MetaType -> Constraint -> Constraint
substituteVariable var replacement constraint =
    case constraint of
        Equality vars metaType1 metaType2 ->
            if Set.member var vars then
                equality
                    (metaType1 |> MetaType.substituteVariable var replacement)
                    (metaType2 |> MetaType.substituteVariable var replacement)

            else
                constraint

        Class vars metaType cls ->
            if Set.member var vars then
                class
                    (metaType |> MetaType.substituteVariable var replacement)
                    cls

            else
                constraint


substituteVariables : Dict Variable MetaType -> Constraint -> Constraint
substituteVariables replacements constraint =
    case constraint of
        Equality _ metaType1 metaType2 ->
            equality
                (metaType1 |> MetaType.substituteVariables replacements)
                (metaType2 |> MetaType.substituteVariables replacements)

        Class _ metaType cls ->
            class
                (metaType |> MetaType.substituteVariables replacements)
                cls


isTrivial : Constraint -> Bool
isTrivial constraint =
    case constraint of
        Equality _ metaType1 metaType2 ->
            metaType1 == metaType2

        Class _ _ _ ->
            False


isRecursive : Constraint -> Bool
isRecursive constraint =
    case constraint of
        Equality _ metaType1 metaType2 ->
            let
                rawMetaType1 =
                    MetaType.removeAliases metaType1

                rawMetaType2 =
                    MetaType.removeAliases metaType2
            in
            (rawMetaType1 /= rawMetaType2)
                && (MetaType.variables rawMetaType1 |> Set.isEmpty |> not)
                && (MetaType.variables rawMetaType2 |> Set.isEmpty |> not)
                && (MetaType.contains rawMetaType1 rawMetaType2 || MetaType.contains rawMetaType2 rawMetaType1)

        Class _ _ _ ->
            False


toString : Constraint -> String
toString constraint =
    case constraint of
        Equality _ metaType1 metaType2 ->
            String.concat
                [ MetaType.toString metaType1
                , " == "
                , MetaType.toString metaType2
                ]

        Class _ metaType c ->
            String.concat
                [ MetaType.toString metaType
                , " is a "
                , Class.toString c
                ]
