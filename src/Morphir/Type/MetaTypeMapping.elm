module Morphir.Type.MetaTypeMapping exposing (..)

import Dict exposing (Dict)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, metaAlias, metaFun, metaRecord, metaRef, metaTuple, metaUnit, metaVar)
import Morphir.Type.Solve as SolutionMap exposing (SolutionMap)
import Set exposing (Set)


type LookupError
    = CouldNotFindConstructor FQName
    | CouldNotFindValue FQName
    | CouldNotFindAlias FQName
    | ExpectedAlias FQName


lookupConstructor : Variable -> IR -> FQName -> Result LookupError MetaType
lookupConstructor baseVar ir ctorFQN =
    ir
        |> IR.lookupTypeConstructor ctorFQN
        |> Maybe.map
            (\( typeFQN, paramNames, ctorArgs ) ->
                ctorToMetaType baseVar ir typeFQN paramNames (ctorArgs |> List.map Tuple.second)
            )
        |> Result.fromMaybe (CouldNotFindConstructor ctorFQN)


lookupValue : Variable -> IR -> FQName -> Result LookupError MetaType
lookupValue baseVar ir valueFQN =
    ir
        |> IR.lookupValueSpecification valueFQN
        |> Maybe.map (valueSpecToMetaType baseVar ir)
        |> Result.fromMaybe (CouldNotFindValue valueFQN)


lookupAliasedType : IR -> FQName -> List (Type ()) -> Result LookupError (Type ())
lookupAliasedType ir typeFQN concreteTypeParams =
    ir
        |> IR.lookupTypeSpecification typeFQN
        |> Result.fromMaybe (CouldNotFindAlias typeFQN)
        |> Result.andThen
            (\typeSpec ->
                case typeSpec of
                    Type.TypeAliasSpecification typeParamNames tpe ->
                        tpe
                            |> Type.substituteTypeVariables
                                (List.map2 Tuple.pair typeParamNames concreteTypeParams
                                    |> Dict.fromList
                                )
                            |> Ok

                    _ ->
                        Err (ExpectedAlias typeFQN)
            )


metaTypeToConcreteType : SolutionMap -> MetaType -> Type ()
metaTypeToConcreteType solutionMap metaType =
    case metaType of
        MetaVar metaVar ->
            solutionMap
                |> SolutionMap.get metaVar
                |> Maybe.map (metaTypeToConcreteType solutionMap)
                |> Maybe.withDefault (metaVar |> MetaType.toName |> Type.Variable ())

        MetaTuple _ metaElems ->
            Type.Tuple ()
                (metaElems
                    |> List.map (metaTypeToConcreteType solutionMap)
                )

        MetaRecord _ extends metaFields ->
            case extends of
                Nothing ->
                    Type.Record ()
                        (metaFields
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldType ) ->
                                    Type.Field fieldName
                                        (metaTypeToConcreteType solutionMap fieldType)
                                )
                        )

                Just baseType ->
                    Type.ExtensibleRecord ()
                        (baseType |> MetaType.toName)
                        (metaFields
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, fieldType ) ->
                                    Type.Field fieldName
                                        (metaTypeToConcreteType solutionMap fieldType)
                                )
                        )

        MetaFun _ argType returnType ->
            Type.Function ()
                (metaTypeToConcreteType solutionMap argType)
                (metaTypeToConcreteType solutionMap returnType)

        MetaRef _ fQName args _ ->
            Type.Reference () fQName (args |> List.map (metaTypeToConcreteType solutionMap))

        MetaUnit ->
            Type.Unit ()


concreteTypeToMetaType : Variable -> IR -> Dict Name Variable -> Type () -> MetaType
concreteTypeToMetaType baseVar ir varToMeta tpe =
    case tpe of
        Type.Variable _ varName ->
            varToMeta
                |> Dict.get varName
                -- this should never happen
                |> Maybe.withDefault baseVar
                |> metaVar

        Type.Reference _ fQName args ->
            let
                resolveAliases : FQName -> List (Type ()) -> MetaType
                resolveAliases fqn ars =
                    let
                        metaArgs =
                            ars |> List.map (concreteTypeToMetaType baseVar ir varToMeta)
                    in
                    lookupAliasedType ir fqn ars
                        |> Result.map (concreteTypeToMetaType baseVar ir varToMeta >> metaAlias fqn metaArgs)
                        |> Result.withDefault (metaRef fqn metaArgs)
            in
            resolveAliases fQName args

        Type.Tuple _ elemTypes ->
            metaTuple
                (elemTypes
                    |> List.map (concreteTypeToMetaType baseVar ir varToMeta)
                )

        Type.Record _ fieldTypes ->
            metaRecord Nothing
                (fieldTypes
                    |> List.map
                        (\field ->
                            ( field.name, concreteTypeToMetaType baseVar ir varToMeta field.tpe )
                        )
                    |> Dict.fromList
                )

        Type.ExtensibleRecord _ subjectName fieldTypes ->
            metaRecord
                (varToMeta
                    |> Dict.get subjectName
                )
                (fieldTypes
                    |> List.map
                        (\field ->
                            ( field.name, concreteTypeToMetaType baseVar ir varToMeta field.tpe )
                        )
                    |> Dict.fromList
                )

        Type.Function _ argType returnType ->
            metaFun
                (concreteTypeToMetaType baseVar ir varToMeta argType)
                (concreteTypeToMetaType baseVar ir varToMeta returnType)

        Type.Unit _ ->
            metaUnit


ctorToMetaType : Variable -> IR -> FQName -> List Name -> List (Type ()) -> MetaType
ctorToMetaType baseVar ir ctorFQName paramNames ctorArgs =
    let
        argVariables : Set Name
        argVariables =
            ctorArgs
                |> List.map Type.collectVariables
                |> List.foldl Set.union Set.empty

        allVariables : Set Name
        allVariables =
            paramNames
                |> Set.fromList
                |> Set.union argVariables

        varToMeta : Dict Name Variable
        varToMeta =
            allVariables
                |> concreteVarsToMetaVars baseVar

        recurse cargs =
            case cargs of
                [] ->
                    metaRef ctorFQName
                        (paramNames
                            |> List.map
                                (\paramName ->
                                    varToMeta
                                        |> Dict.get paramName
                                        -- this should never happen
                                        |> Maybe.withDefault baseVar
                                        |> metaVar
                                )
                        )

                firstCtorArg :: restOfCtorArgs ->
                    metaFun
                        (concreteTypeToMetaType baseVar ir varToMeta firstCtorArg)
                        (recurse restOfCtorArgs)
    in
    recurse ctorArgs


valueSpecToMetaType : Variable -> IR -> Value.Specification () -> MetaType
valueSpecToMetaType baseVar ir valueSpec =
    let
        specToFunctionType : List (Type ()) -> Type () -> Type ()
        specToFunctionType argTypes returnType =
            case argTypes of
                [] ->
                    returnType

                firstArg :: restOfArgs ->
                    Type.Function () firstArg (specToFunctionType restOfArgs returnType)

        functionType : Type ()
        functionType =
            specToFunctionType (valueSpec.inputs |> List.map Tuple.second) valueSpec.output

        varToMeta : Dict Name Variable
        varToMeta =
            functionType
                |> Type.collectVariables
                |> concreteVarsToMetaVars baseVar
    in
    concreteTypeToMetaType baseVar ir varToMeta functionType


concreteVarsToMetaVars : Variable -> Set Name -> Dict Name Variable
concreteVarsToMetaVars baseVar variables =
    variables
        |> Set.toList
        |> List.foldl
            (\varName ( metaVarSoFar, varToMetaSoFar ) ->
                let
                    nextVar =
                        metaVarSoFar |> MetaType.subVariable
                in
                ( nextVar
                , varToMetaSoFar
                    |> Dict.insert varName nextVar
                )
            )
            ( baseVar, Dict.empty )
        |> Tuple.second
