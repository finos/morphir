module Morphir.Type.ConstraintSet exposing (..)

import Dict
import Morphir.Type.Constraint as Constraint exposing (Constraint(..))
import Morphir.Type.MetaType exposing (MetaType)
import Morphir.Type.MetaVar exposing (Variable)
import Morphir.Type.SolutionMap exposing (SolutionMap(..))


type ConstraintSet
    = ConstraintSet (List Constraint)


empty : ConstraintSet
empty =
    ConstraintSet []


singleton : Constraint -> ConstraintSet
singleton constraint =
    ConstraintSet [ constraint ]


isEmpty : ConstraintSet -> Bool
isEmpty (ConstraintSet constraints) =
    List.isEmpty constraints


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


union : ConstraintSet -> ConstraintSet -> ConstraintSet
union constraintSet1 (ConstraintSet constraints2) =
    List.foldl insert constraintSet1 constraints2


substituteVariable : Variable -> MetaType -> ConstraintSet -> ConstraintSet
substituteVariable var replacement (ConstraintSet constraints) =
    ConstraintSet
        (constraints
            |> List.map (Constraint.substitute var replacement)
        )


applySubstitutions : SolutionMap -> ConstraintSet -> ConstraintSet
applySubstitutions (SolutionMap substitutions) constraintSet =
    substitutions
        |> Dict.toList
        |> List.foldl
            (\( var, replacement ) soFar ->
                soFar |> substituteVariable var replacement
            )
            constraintSet
