module Morphir.Type.ConstraintSet exposing (..)

import Dict exposing (Dict)
import Morphir.Type.Constraint as Constraint exposing (Constraint(..))
import Morphir.Type.MetaType exposing (MetaType(..), Variable)
import Morphir.Type.Solve as Solve exposing (SolutionMap(..))
import Set exposing (Set)


type ConstraintSet
    = ConstraintSet (List Constraint)


empty : ConstraintSet
empty =
    ConstraintSet []


singleton : Constraint -> ConstraintSet
singleton constraint =
    fromList [ constraint ]


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



--simplify : ConstraintSet -> ( ConstraintSet, Dict Variable (Set Variable) )
--simplify ((ConstraintSet constraints) as constraintSet) =
--    let
--        variableConstraints : List ( Variable, Variable )
--        variableConstraints =
--            constraints
--                |> List.filterMap
--                    (\constraint ->
--                        case constraint of
--                            Equality _ (MetaVar var1) (MetaVar var2) ->
--                                if var1 < var2 then
--                                    Just ( var1, var2 )
--
--                                else
--                                    Just ( var2, var1 )
--
--                            _ ->
--                                Nothing
--                    )
--
--        substituteOne : Variable -> Variable -> List ( Variable, Variable ) -> List ( Variable, Variable )
--        substituteOne varToReplace replacement vars =
--            vars
--                |> List.map
--                    (\( v1, v2 ) ->
--                        let
--                            nv1 =
--                                if v1 == varToReplace then
--                                    replacement
--
--                                else
--                                    v1
--
--                            nv2 =
--                                if v2 == varToReplace then
--                                    replacement
--
--                                else
--                                    v2
--                        in
--                        if nv1 < nv2 then
--                            ( nv1, nv2 )
--
--                        else
--                            ( nv2, nv1 )
--                    )
--
--        substituteAll : Set Variable -> Variable -> List ( Variable, Variable ) -> List ( Variable, Variable )
--        substituteAll varsToReplace replacement vars =
--            varsToReplace
--                |> Set.foldl
--                    (\varToReplace -> substituteOne varToReplace replacement)
--                    vars
--
--        cleanUpVariables : List ( Variable, Variable ) -> List ( Variable, Variable )
--        cleanUpVariables vars =
--            vars
--                |> List.filter (\( v1, v2 ) -> v1 /= v2)
--                |> Set.fromList
--                |> Set.toList
--
--        equivalenceGroups : List ( Variable, Variable ) -> Dict Variable (Set Variable) -> Dict Variable (Set Variable)
--        equivalenceGroups equivalentVars groupsSoFar =
--            case equivalentVars of
--                ( var1, var2 ) :: restOfEquivalentVars ->
--                    case groupsSoFar |> Dict.get var1 of
--                        Just var1Group ->
--                            if Set.member var2 var1Group then
--                                equivalenceGroups restOfEquivalentVars groupsSoFar
--
--                            else
--                                case groupsSoFar |> Dict.get var2 of
--                                    Just var2Group ->
--                                        let
--                                            newGroups =
--                                                groupsSoFar
--                                                    |> Dict.insert var1 (Set.union var1Group var2Group)
--                                                    |> Dict.remove var2
--
--                                            newEquivalentVars =
--                                                restOfEquivalentVars
--                                                    |> substituteAll var2Group var1
--                                                    |> cleanUpVariables
--                                        in
--                                        equivalenceGroups newEquivalentVars newGroups
--
--                                    Nothing ->
--                                        let
--                                            newGroups =
--                                                groupsSoFar
--                                                    |> Dict.insert var1 (Set.insert var2 var1Group)
--
--                                            newEquivalentVars =
--                                                restOfEquivalentVars
--                                                    |> substituteOne var2 var1
--                                                    |> cleanUpVariables
--                                        in
--                                        equivalenceGroups newEquivalentVars newGroups
--
--                        Nothing ->
--                            let
--                                newGroups =
--                                    groupsSoFar
--                                        |> Dict.insert var1 (Set.fromList [ var1, var2 ])
--
--                                newEquivalentVars =
--                                    restOfEquivalentVars
--                                        |> substituteOne var2 var1
--                                        |> cleanUpVariables
--                            in
--                            equivalenceGroups newEquivalentVars newGroups
--
--                [] ->
--                    groupsSoFar
--
--        groups : Dict Variable (Set Variable)
--        groups =
--            equivalenceGroups variableConstraints Dict.empty
--
--        simplifiedConstraints : ConstraintSet
--        simplifiedConstraints =
--            groups
--                |> Dict.toList
--                |> List.concatMap
--                    (\( newVar, oldVars ) ->
--                        oldVars
--                            |> Set.toList
--                            |> List.map (Tuple.pair newVar)
--                    )
--                |> List.foldl
--                    (\( newVar, oldVar ) constraintsSofar ->
--                        substituteVariable oldVar (MetaVar newVar) constraintsSofar
--                    )
--                    constraintSet
--    in
--    ( simplifiedConstraints, groups )
