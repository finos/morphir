module Morphir.Type.Constraint exposing (..)

import Dict exposing (Dict)
import Morphir.Type.Class exposing (Class)
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable)
import Set


type Constraint
    = Equality MetaType MetaType
    | Class MetaType Class


equality : MetaType -> MetaType -> Constraint
equality =
    Equality


class : MetaType -> Class -> Constraint
class =
    Class


equivalent : Constraint -> Constraint -> Bool
equivalent constraint1 constraint2 =
    if constraint1 == constraint2 then
        True

    else
        case ( constraint1, constraint2 ) of
            ( Equality a1 a2, Equality b1 b2 ) ->
                (a1 == b1 && a2 == b2) || (a1 == b2 && a2 == b1)

            _ ->
                False


substituteVariable : Variable -> MetaType -> Constraint -> Constraint
substituteVariable var replacement constraint =
    case constraint of
        Equality metaType1 metaType2 ->
            Equality
                (metaType1 |> MetaType.substituteVariable var replacement)
                (metaType2 |> MetaType.substituteVariable var replacement)

        Class metaType cls ->
            Class
                (metaType |> MetaType.substituteVariable var replacement)
                cls


substituteVariables : Dict Variable MetaType -> Constraint -> Constraint
substituteVariables replacements constraint =
    case constraint of
        Equality metaType1 metaType2 ->
            Equality
                (metaType1 |> MetaType.substituteVariables replacements)
                (metaType2 |> MetaType.substituteVariables replacements)

        Class metaType cls ->
            Class
                (metaType |> MetaType.substituteVariables replacements)
                cls


isTrivial : Constraint -> Bool
isTrivial constraint =
    case constraint of
        Equality metaType1 metaType2 ->
            metaType1 == metaType2

        Class _ _ ->
            False


isRecursive : Constraint -> Bool
isRecursive constraint =
    case constraint of
        Equality metaType1 metaType2 ->
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

        Class _ _ ->
            False
