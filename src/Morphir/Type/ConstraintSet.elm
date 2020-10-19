module Morphir.Type.ConstraintSet exposing (..)

import Morphir.Type.Constraint as Constraint exposing (Constraint)
import Morphir.Type.MetaType as MetaType exposing (MetaType)


type ConstraintSet
    = ConstraintSet (List Constraint)


empty : ConstraintSet
empty =
    ConstraintSet []


member : Constraint -> ConstraintSet -> Bool
member constraint (ConstraintSet constraints) =
    List.any (Constraint.equivalent constraint) constraints


insert : Constraint -> ConstraintSet -> ConstraintSet
insert constraint ((ConstraintSet constraints) as constraintSet) =
    if member constraint constraintSet then
        constraintSet

    else
        ConstraintSet (constraint :: constraints)


fromList : List Constraint -> ConstraintSet
fromList list =
    List.foldl insert empty list


substitute : MetaType.Variable -> MetaType -> ConstraintSet -> ConstraintSet
substitute var replacement (ConstraintSet constraints) =
    ConstraintSet
        (constraints
            |> List.map (Constraint.substitute var replacement)
        )

take : ConstraintSet -> ( ConstraintSet, Constraint )
take (ConstraintSet constraints)