module Morphir.Type.Constraint exposing (..)

import Morphir.Type.Class exposing (Class)
import Morphir.Type.MetaType as MetaType exposing (MetaType, Variable)


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


substitute : Variable -> MetaType -> Constraint -> Constraint
substitute var replacement constraint =
    case constraint of
        Equality metaType1 metaType2 ->
            Equality
                (metaType1 |> MetaType.substituteVariable var replacement)
                (metaType2 |> MetaType.substituteVariable var replacement)

        Class metaType cls ->
            Class
                (metaType |> MetaType.substituteVariable var replacement)
                cls
