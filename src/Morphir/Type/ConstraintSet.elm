module Morphir.Type.ConstraintSet exposing (..)

import Dict
import Morphir.Type.Constraint as Constraint exposing (Constraint(..))
import Morphir.Type.MetaType exposing (MetaType, Variable)
import Morphir.Type.Solve as Solve exposing (SolutionMap(..))


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
    if Constraint.isTrivial constraint || member constraint constraintSet then
        constraintSet

    else
        ConstraintSet (constraint :: constraints)


fromList : List Constraint -> ConstraintSet
fromList list =
    List.foldl insert empty list


toList : ConstraintSet -> List Constraint
toList (ConstraintSet list) =
    list


union : ConstraintSet -> ConstraintSet -> ConstraintSet
union constraintSet1 (ConstraintSet constraints2) =
    List.foldl insert constraintSet1 constraints2


concat : List ConstraintSet -> ConstraintSet
concat constraintSets =
    List.foldl union empty constraintSets


substituteVariable : Variable -> MetaType -> ConstraintSet -> ConstraintSet
substituteVariable var replacement (ConstraintSet constraints) =
    ConstraintSet
        (constraints
            |> List.filterMap
                (\constraint ->
                    let
                        newConstraint =
                            Constraint.substituteVariable var replacement constraint
                    in
                    if Constraint.isTrivial newConstraint then
                        Nothing

                    else
                        Just newConstraint
                )
        )


applySubstitutions : SolutionMap -> ConstraintSet -> ConstraintSet
applySubstitutions substitutions constraintSet =
    substitutions
        |> Solve.toList
        |> List.foldl
            (\( var, replacement ) soFar ->
                soFar |> substituteVariable var replacement
            )
            constraintSet
