module Morphir.Type.Solve exposing (..)

import Dict exposing (Dict)
import Morphir.IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.ListOfResults as ListOfResults
import Morphir.Type.Constraint exposing (Constraint(..))
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, isNamedVariable, metaFun, metaRecord, metaRef, metaTuple, metaVar, wrapInAliases)


type SolutionMap
    = SolutionMap (Dict Variable MetaType)


emptySolution : SolutionMap
emptySolution =
    SolutionMap Dict.empty


isEmptySolution : SolutionMap -> Bool
isEmptySolution (SolutionMap solutions) =
    Dict.isEmpty solutions


singleSolution : Aliases -> Variable -> MetaType -> SolutionMap
singleSolution aliases var metaType =
    SolutionMap (Dict.singleton var (wrapInAliases aliases metaType))


fromList : List ( Variable, MetaType ) -> SolutionMap
fromList list =
    list
        |> Dict.fromList
        |> SolutionMap


toList : SolutionMap -> List ( Variable, MetaType )
toList (SolutionMap dict) =
    dict |> Dict.toList


get : Variable -> SolutionMap -> Maybe MetaType
get var (SolutionMap dict) =
    Dict.get var dict


diff : SolutionMap -> SolutionMap -> SolutionMap
diff (SolutionMap dict1) (SolutionMap dict2) =
    dict1
        |> Dict.toList
        |> List.filterMap
            (\( k, v1 ) ->
                case dict2 |> Dict.get k of
                    Just v2 ->
                        if v1 == v2 then
                            Nothing

                        else
                            Just ( k, v1 )

                    Nothing ->
                        Just ( k, v1 )
            )
        |> Dict.fromList
        |> SolutionMap


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
findSubstitution ir constraints =
    case constraints of
        [] ->
            Ok Nothing

        firstConstraint :: restOfConstraints ->
            case firstConstraint of
                Equality _ metaType1 metaType2 ->
                    unifyMetaType ir [] metaType1 metaType2
                        |> Result.andThen
                            (\solutions ->
                                if isEmptySolution solutions then
                                    findSubstitution ir restOfConstraints

                                else
                                    Ok (Just solutions)
                            )

                Class _ _ _ ->
                    findSubstitution ir restOfConstraints


addSolution : IR -> Variable -> MetaType -> SolutionMap -> Result UnificationError SolutionMap
addSolution ir var newSolution (SolutionMap currentSolutions) =
    let
        substitutedNewSolution : MetaType
        substitutedNewSolution =
            MetaType.substituteVariables currentSolutions newSolution
    in
    case Dict.get var currentSolutions of
        Just existingSolution ->
            -- Unify with the existing solution
            unifyMetaType ir [] existingSolution substitutedNewSolution
                |> Result.map
                    (\(SolutionMap newSubstitutions) ->
                        -- If it unifies apply the substitutions to the existing solution and add all new substitutions
                        currentSolutions
                            |> Dict.insert var
                                (existingSolution
                                    |> MetaType.substituteVariables newSubstitutions
                                )
                            |> Dict.union newSubstitutions
                            |> SolutionMap
                            |> substituteVariable var substitutedNewSolution
                    )

        Nothing ->
            -- Simply substitute and insert the new solution
            currentSolutions
                |> Dict.insert var substitutedNewSolution
                |> SolutionMap
                |> substituteVariable var substitutedNewSolution
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


type alias Aliases =
    List ( FQName, List MetaType )


unifyMetaType : IR -> Aliases -> MetaType -> MetaType -> Result UnificationError SolutionMap
unifyMetaType ir aliases metaType1 metaType2 =
    let
        handleCommon mt2 specific =
            case mt2 of
                MetaVar var2 ->
                    unifyVariable aliases var2 metaType1

                MetaRef _ ref2 args2 (Just aliasedType2) ->
                    unifyMetaType ir (( ref2, args2 ) :: aliases) aliasedType2 metaType1

                _ ->
                    specific mt2
    in
    if metaType1 == metaType2 then
        Ok emptySolution

    else
        case metaType1 of
            MetaVar var1 ->
                unifyVariable aliases var1 metaType2

            MetaTuple _ elems1 ->
                handleCommon metaType2
                    (unifyTuple ir aliases elems1)

            MetaRef _ ref1 args1 Nothing ->
                handleCommon metaType2
                    (unifyRef ir aliases ref1 args1)

            MetaRef _ ref1 args1 (Just aliasedType1) ->
                unifyMetaType ir (( ref1, args1 ) :: aliases) aliasedType1 metaType2

            MetaFun _ arg1 return1 ->
                handleCommon metaType2
                    (unifyFun ir aliases arg1 return1)

            MetaRecord _ extends1 fields1 ->
                handleCommon metaType2
                    (unifyRecord ir aliases extends1 fields1)

            MetaUnit ->
                handleCommon metaType2
                    (unifyUnit aliases)


unifyVariable : Aliases -> Variable -> MetaType -> Result UnificationError SolutionMap
unifyVariable aliases var1 metaType2 =
    case metaType2 of
        MetaVar var2 ->
            if isNamedVariable var1 then
                Ok (singleSolution aliases var2 (metaVar var1))

            else
                Ok (singleSolution aliases var1 metaType2)

        _ ->
            Ok (singleSolution aliases var1 metaType2)


unifyTuple : IR -> Aliases -> List MetaType -> MetaType -> Result UnificationError SolutionMap
unifyTuple ir aliases elems1 metaType2 =
    case metaType2 of
        MetaTuple _ elems2 ->
            if List.length elems1 == List.length elems2 then
                List.map2 (unifyMetaType ir []) elems1 elems2
                    |> ListOfResults.liftAllErrors
                    |> Result.mapError UnificationErrors
                    |> Result.andThen (concatSolutions ir)

            else
                Err (CouldNotUnify TuplesOfDifferentSize (metaTuple elems1) metaType2)

        _ ->
            Err (CouldNotUnify NoUnificationRule (metaTuple elems1) metaType2)


unifyRef : IR -> Aliases -> FQName -> List MetaType -> MetaType -> Result UnificationError SolutionMap
unifyRef ir aliases ref1 args1 metaType2 =
    case metaType2 of
        MetaRef _ ref2 args2 Nothing ->
            if ref1 == ref2 then
                if List.length args1 == List.length args2 then
                    List.map2 (unifyMetaType ir []) args1 args2
                        |> ListOfResults.liftAllErrors
                        |> Result.mapError UnificationErrors
                        |> Result.andThen (concatSolutions ir)

                else
                    Err (CouldNotUnify TuplesOfDifferentSize (metaRef ref1 args1) metaType2)

            else
                Err (CouldNotUnify RefMismatch (metaRef ref1 args1) metaType2)

        MetaRecord _ extends2 fields2 ->
            unifyRecord ir aliases extends2 fields2 (metaRef ref1 args1)

        _ ->
            Err (CouldNotUnify NoUnificationRule (metaRef ref1 args1) metaType2)


unifyFun : IR -> Aliases -> MetaType -> MetaType -> MetaType -> Result UnificationError SolutionMap
unifyFun ir aliases arg1 return1 metaType2 =
    case metaType2 of
        MetaFun _ arg2 return2 ->
            Result.andThen identity
                (Result.map2 (mergeSolutions ir)
                    (unifyMetaType ir [] arg1 arg2)
                    (unifyMetaType ir [] return1 return2)
                )

        _ ->
            Err (CouldNotUnify NoUnificationRule (metaFun arg1 return1) metaType2)


unifyRecord : IR -> Aliases -> Maybe Variable -> Dict Name MetaType -> MetaType -> Result UnificationError SolutionMap
unifyRecord refs aliases extends1 fields1 metaType2 =
    case metaType2 of
        MetaRecord _ extends2 fields2 ->
            unifyFields refs extends1 fields1 extends2 fields2
                |> Result.andThen
                    (\( newFields, fieldSolutions ) ->
                        case extends1 of
                            Just extendsVar1 ->
                                mergeSolutions
                                    refs
                                    fieldSolutions
                                    (singleSolution aliases
                                        extendsVar1
                                        (metaRecord extends2 newFields)
                                    )

                            Nothing ->
                                case extends2 of
                                    Just extendsVar2 ->
                                        mergeSolutions
                                            refs
                                            fieldSolutions
                                            (singleSolution aliases
                                                extendsVar2
                                                (metaRecord extends1 newFields)
                                            )

                                    Nothing ->
                                        Ok fieldSolutions
                    )

        _ ->
            Err (CouldNotUnify NoUnificationRule (metaRecord extends1 fields1) metaType2)


unifyFields : IR -> Maybe Variable -> Dict Name MetaType -> Maybe Variable -> Dict Name MetaType -> Result UnificationError ( Dict Name MetaType, SolutionMap )
unifyFields ir oldExtends oldFields newExtends newFields =
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
                            |> Result.andThen (unifyMetaType ir [] originalType)
                    )
                |> ListOfResults.liftAllErrors
                |> Result.mapError UnificationErrors
                |> Result.andThen (concatSolutions ir)

        unifiedFields : Dict Name MetaType
        unifiedFields =
            Dict.union commonFieldsOldType
                (Dict.union extraOldFields extraNewFields)
    in
    if oldExtends == Nothing && not (Dict.isEmpty extraNewFields) then
        Err (CouldNotUnify FieldMismatch (metaRecord oldExtends oldFields) (metaRecord newExtends newFields))

    else if newExtends == Nothing && not (Dict.isEmpty extraOldFields) then
        Err (CouldNotUnify FieldMismatch (metaRecord oldExtends oldFields) (metaRecord newExtends newFields))

    else
        fieldSolutionsResult
            |> Result.map (Tuple.pair unifiedFields)


unifyUnit : Aliases -> MetaType -> Result UnificationError SolutionMap
unifyUnit aliases metaType2 =
    case metaType2 of
        MetaUnit ->
            Ok emptySolution

        _ ->
            Err (CouldNotUnify NoUnificationRule MetaUnit metaType2)
