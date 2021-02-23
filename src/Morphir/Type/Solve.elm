module Morphir.Type.Solve exposing (..)

import Dict exposing (Dict)
import Morphir.IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.ListOfResults as ListOfResults
import Morphir.Type.Constraint exposing (Constraint(..))
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable)


type SolutionMap
    = SolutionMap (Dict Variable MetaType)


emptySolution : SolutionMap
emptySolution =
    SolutionMap Dict.empty


isEmptySolution : SolutionMap -> Bool
isEmptySolution (SolutionMap solutions) =
    Dict.isEmpty solutions


singleSolution : Variable -> MetaType -> SolutionMap
singleSolution var metaType =
    SolutionMap (Dict.singleton var metaType)


fromList : List ( Variable, MetaType ) -> SolutionMap
fromList list =
    list
        |> Dict.fromList
        |> SolutionMap


get : Variable -> SolutionMap -> Maybe MetaType
get var (SolutionMap dict) =
    Dict.get var dict


substituteVariable : Variable -> MetaType -> SolutionMap -> SolutionMap
substituteVariable var replacement (SolutionMap solutions) =
    SolutionMap
        (solutions
            |> Dict.map
                (\_ metaType ->
                    metaType |> MetaType.substituteVariable var replacement
                )
        )


type UnificationError
    = UnificationErrors (List UnificationError)
    | CouldNotUnify UnificationErrorType MetaType MetaType
    | CouldNotFindField Name


type UnificationErrorType
    = NoUnificationRule
    | TuplesOfDifferentSize
    | RefMismatch
    | FieldMismatch


findSubstitution : IR -> List Constraint -> Result UnificationError (Maybe SolutionMap)
findSubstitution refs constraints =
    case constraints of
        [] ->
            Ok Nothing

        firstConstraint :: restOfConstraints ->
            case firstConstraint of
                Equality metaType1 metaType2 ->
                    unifyMetaType refs [] metaType1 metaType2
                        |> Result.andThen
                            (\solutions ->
                                if isEmptySolution solutions then
                                    findSubstitution refs restOfConstraints

                                else
                                    Ok (Just solutions)
                            )

                Class _ _ ->
                    findSubstitution refs restOfConstraints


addSolution : IR -> Variable -> MetaType -> SolutionMap -> Result UnificationError SolutionMap
addSolution refs var newSolution (SolutionMap currentSolutions) =
    case Dict.get var currentSolutions of
        Just existingSolution ->
            -- Unify with the existing solution
            unifyMetaType refs [] existingSolution newSolution
                |> Result.map
                    (\(SolutionMap newSubstitutions) ->
                        -- If it unifies apply the substitutions to the existing solution and add all new substitutions
                        SolutionMap
                            (currentSolutions
                                |> Dict.insert var
                                    (existingSolution
                                        |> MetaType.substituteVariables (Dict.toList newSubstitutions)
                                    )
                                |> Dict.union newSubstitutions
                            )
                    )

        Nothing ->
            -- Simply substitute and insert the new solution
            currentSolutions
                |> Dict.insert var newSolution
                |> SolutionMap
                |> substituteVariable var newSolution
                |> Ok


mergeSolutions : IR -> SolutionMap -> SolutionMap -> Result UnificationError SolutionMap
mergeSolutions refs (SolutionMap newSolutions) currentSolutions =
    newSolutions
        |> Dict.toList
        |> List.foldl
            (\( var, newSolution ) solutionsSoFar ->
                solutionsSoFar
                    |> Result.andThen (addSolution refs var newSolution)
            )
            (Ok currentSolutions)


concatSolutions : IR -> List SolutionMap -> Result UnificationError SolutionMap
concatSolutions refs solutionMaps =
    solutionMaps
        |> List.foldl
            (\nextSolutions resultSoFar ->
                resultSoFar
                    |> Result.andThen
                        (\solutionsSoFar ->
                            mergeSolutions refs solutionsSoFar nextSolutions
                        )
            )
            (Ok emptySolution)


unifyMetaType : IR -> List FQName -> MetaType -> MetaType -> Result UnificationError SolutionMap
unifyMetaType refs aliases metaType1 metaType2 =
    if metaType1 == metaType2 then
        Ok emptySolution

    else
        case metaType1 of
            MetaVar var1 ->
                unifyVariable aliases var1 metaType2

            MetaTuple elems1 ->
                unifyTuple refs aliases elems1 metaType2

            MetaRef ref1 ->
                unifyRef refs aliases ref1 metaType2

            MetaApply fun1 arg1 ->
                unifyApply refs aliases fun1 arg1 metaType2

            MetaFun arg1 return1 ->
                unifyFun refs aliases arg1 return1 metaType2

            MetaRecord extends1 fields1 ->
                unifyRecord refs aliases extends1 fields1 metaType2

            MetaUnit ->
                unifyUnit aliases metaType2

            MetaAlias alias subject1 ->
                unifyMetaType refs (alias :: aliases) subject1 metaType2


unifyVariable : List FQName -> Variable -> MetaType -> Result UnificationError SolutionMap
unifyVariable aliases var1 metaType2 =
    Ok (singleSolution var1 (wrapInAliases aliases metaType2))


unifyTuple : IR -> List FQName -> List MetaType -> MetaType -> Result UnificationError SolutionMap
unifyTuple refs aliases elems1 metaType2 =
    case metaType2 of
        MetaVar var2 ->
            unifyVariable aliases var2 (MetaTuple elems1)

        MetaTuple elems2 ->
            if List.length elems1 == List.length elems2 then
                List.map2 (unifyMetaType refs aliases) elems1 elems2
                    |> ListOfResults.liftAllErrors
                    |> Result.mapError UnificationErrors
                    |> Result.andThen (concatSolutions refs)

            else
                Err (CouldNotUnify TuplesOfDifferentSize (MetaTuple elems1) metaType2)

        _ ->
            Err (CouldNotUnify NoUnificationRule (MetaTuple elems1) metaType2)


unifyRef : IR -> List FQName -> FQName -> MetaType -> Result UnificationError SolutionMap
unifyRef refs aliases ref1 metaType2 =
    case metaType2 of
        MetaAlias alias subject2 ->
            unifyRef refs (alias :: aliases) ref1 subject2

        MetaVar var2 ->
            unifyVariable aliases var2 (MetaRef ref1)

        MetaRef ref2 ->
            if ref1 == ref2 then
                Ok emptySolution

            else
                Err (CouldNotUnify RefMismatch (MetaRef ref1) metaType2)

        MetaRecord extends2 fields2 ->
            unifyRecord refs aliases extends2 fields2 (MetaRef ref1)

        _ ->
            Err (CouldNotUnify NoUnificationRule (MetaRef ref1) metaType2)


unifyApply : IR -> List FQName -> MetaType -> MetaType -> MetaType -> Result UnificationError SolutionMap
unifyApply refs aliases fun1 arg1 metaType2 =
    case metaType2 of
        MetaAlias alias subject2 ->
            unifyApply refs (alias :: aliases) fun1 arg1 subject2

        MetaVar var2 ->
            unifyVariable aliases var2 (MetaApply fun1 arg1)

        MetaApply fun2 arg2 ->
            Result.andThen identity
                (Result.map2 (mergeSolutions refs)
                    (unifyMetaType refs aliases fun1 fun2)
                    (unifyMetaType refs aliases arg1 arg2)
                )

        _ ->
            Err (CouldNotUnify NoUnificationRule (MetaApply fun1 arg1) metaType2)


unifyFun : IR -> List FQName -> MetaType -> MetaType -> MetaType -> Result UnificationError SolutionMap
unifyFun refs aliases arg1 return1 metaType2 =
    case metaType2 of
        MetaAlias alias subject2 ->
            unifyFun refs (alias :: aliases) arg1 return1 subject2

        MetaVar var2 ->
            unifyVariable aliases var2 (MetaFun arg1 return1)

        MetaFun arg2 return2 ->
            Result.andThen identity
                (Result.map2 (mergeSolutions refs)
                    (unifyMetaType refs aliases arg1 arg2)
                    (unifyMetaType refs aliases return1 return2)
                )

        _ ->
            Err (CouldNotUnify NoUnificationRule (MetaFun arg1 return1) metaType2)


unifyRecord : IR -> List FQName -> Maybe Variable -> Dict Name MetaType -> MetaType -> Result UnificationError SolutionMap
unifyRecord refs aliases extends1 fields1 metaType2 =
    case metaType2 of
        MetaAlias alias subject2 ->
            unifyRecord refs (alias :: aliases) extends1 fields1 subject2

        MetaVar var2 ->
            unifyVariable aliases var2 (MetaRecord extends1 fields1)

        MetaRecord extends2 fields2 ->
            unifyFields refs extends1 fields1 extends2 fields2
                |> Result.andThen
                    (\( newFields, fieldSolutions ) ->
                        case extends1 of
                            Just extendsVar1 ->
                                mergeSolutions
                                    refs
                                    fieldSolutions
                                    (singleSolution extendsVar1
                                        (wrapInAliases aliases (MetaRecord extends2 newFields))
                                    )

                            Nothing ->
                                case extends2 of
                                    Just extendsVar2 ->
                                        mergeSolutions
                                            refs
                                            fieldSolutions
                                            (singleSolution extendsVar2
                                                (wrapInAliases aliases (MetaRecord extends1 newFields))
                                            )

                                    Nothing ->
                                        Ok fieldSolutions
                    )

        _ ->
            Err (CouldNotUnify NoUnificationRule (MetaRecord extends1 fields1) metaType2)


unifyFields : IR -> Maybe Variable -> Dict Name MetaType -> Maybe Variable -> Dict Name MetaType -> Result UnificationError ( Dict Name MetaType, SolutionMap )
unifyFields refs oldExtends oldFields newExtends newFields =
    let
        extraOldFields : Dict Name MetaType
        extraOldFields =
            Dict.diff oldFields newFields

        extraNewFields : Dict Name MetaType
        extraNewFields =
            Dict.diff newFields oldFields

        commonFieldsOldType : Dict Name MetaType
        commonFieldsOldType =
            Dict.intersect oldFields newFields

        fieldSolutionsResult : Result UnificationError SolutionMap
        fieldSolutionsResult =
            commonFieldsOldType
                |> Dict.toList
                |> List.map
                    (\( fieldName, originalType ) ->
                        newFields
                            |> Dict.get fieldName
                            -- this should never happen but needed for type-safety
                            |> Result.fromMaybe (CouldNotFindField fieldName)
                            |> Result.andThen (unifyMetaType refs [] originalType)
                    )
                |> ListOfResults.liftAllErrors
                |> Result.mapError UnificationErrors
                |> Result.andThen (concatSolutions refs)

        unifiedFields : Dict Name MetaType
        unifiedFields =
            Dict.union commonFieldsOldType
                (Dict.union extraOldFields extraNewFields)
    in
    if oldExtends == Nothing && not (Dict.isEmpty extraNewFields) then
        Err (CouldNotUnify FieldMismatch (MetaRecord oldExtends oldFields) (MetaRecord newExtends newFields))

    else if newExtends == Nothing && not (Dict.isEmpty extraOldFields) then
        Err (CouldNotUnify FieldMismatch (MetaRecord oldExtends oldFields) (MetaRecord newExtends newFields))

    else
        fieldSolutionsResult
            |> Result.map (Tuple.pair unifiedFields)


unifyUnit : List FQName -> MetaType -> Result UnificationError SolutionMap
unifyUnit aliases metaType2 =
    case metaType2 of
        MetaAlias alias subject2 ->
            unifyUnit (alias :: aliases) subject2

        MetaVar var2 ->
            unifyVariable aliases var2 MetaUnit

        MetaUnit ->
            Ok emptySolution

        _ ->
            Err (CouldNotUnify NoUnificationRule MetaUnit metaType2)


wrapInAliases : List FQName -> MetaType -> MetaType
wrapInAliases aliases metaType =
    case aliases of
        [] ->
            metaType

        firstAlias :: restOfAliases ->
            MetaAlias firstAlias (wrapInAliases restOfAliases metaType)
