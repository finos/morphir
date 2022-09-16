module Morphir.Type.MetaTypeMapping exposing (..)

import Dict exposing (Dict)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Type.Counter as Counter exposing (Counter)
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, metaAlias, metaClosedRecord, metaFun, metaOpenRecord, metaRecord, metaRef, metaTuple, metaUnit, metaVar)
import Morphir.Type.Solve as SolutionMap exposing (SolutionMap)
import Set exposing (Set)


type LookupError
    = CouldNotFindConstructor FQName
    | CouldNotFindValue FQName
    | CouldNotFindAlias FQName
    | ExpectedAlias FQName


lookupConstructor : IR -> FQName -> Result LookupError (Counter MetaType)
lookupConstructor ir ctorFQN =
    ir
        |> IR.lookupTypeConstructor ctorFQN
        |> Maybe.map
            (\( typeFQN, paramNames, ctorArgs ) ->
                ctorToMetaType ir typeFQN paramNames (ctorArgs |> List.map Tuple.second)
            )
        |> Result.fromMaybe (CouldNotFindConstructor ctorFQN)


lookupValue : IR -> FQName -> Result LookupError (Counter MetaType)
lookupValue ir valueFQN =
    ir
        |> IR.lookupValueSpecification valueFQN
        |> Maybe.map (valueSpecToMetaType ir)
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

        MetaRecord _ recordVar isOpen metaFields ->
            if not isOpen then
                Type.Record ()
                    (metaFields
                        |> Dict.toList
                        |> List.map
                            (\( fieldName, fieldType ) ->
                                Type.Field fieldName
                                    (metaTypeToConcreteType solutionMap fieldType)
                            )
                    )

            else
                Type.ExtensibleRecord ()
                    (recordVar |> MetaType.toName)
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


concreteTypeToMetaType : IR -> Dict Name Variable -> Type () -> Counter MetaType
concreteTypeToMetaType ir varToMeta tpe =
    case tpe of
        Type.Variable _ varName ->
            Counter.next
                (\counter ->
                    varToMeta
                        |> Dict.get varName
                        -- this should never happen
                        |> Maybe.withDefault (MetaType.variableByIndex counter)
                        |> metaVar
                )

        Type.Reference _ fQName args ->
            args
                |> List.map (concreteTypeToMetaType ir varToMeta)
                |> Counter.concat
                |> Counter.andThen
                    (\metaArgs ->
                        lookupAliasedType ir fQName args
                            |> Result.map
                                (\aliasedType ->
                                    concreteTypeToMetaType ir varToMeta aliasedType
                                        |> Counter.map (metaAlias fQName metaArgs)
                                )
                            |> Result.withDefault
                                (Counter.ignore (metaRef fQName metaArgs))
                    )

        Type.Tuple _ elemTypes ->
            elemTypes
                |> List.map (concreteTypeToMetaType ir varToMeta)
                |> Counter.concat
                |> Counter.map metaTuple

        Type.Record _ fieldTypes ->
            Counter.map2 metaClosedRecord
                (Counter.next MetaType.variableByIndex)
                (fieldTypes
                    |> List.map
                        (\field ->
                            concreteTypeToMetaType ir varToMeta field.tpe
                                |> Counter.map (Tuple.pair field.name)
                        )
                    |> Counter.concat
                    |> Counter.map Dict.fromList
                )

        Type.ExtensibleRecord _ subjectName fieldTypes ->
            Counter.map2 metaOpenRecord
                (Counter.next
                    (\counter ->
                        varToMeta
                            |> Dict.get subjectName
                            |> Maybe.withDefault (MetaType.variableByIndex counter)
                    )
                )
                (fieldTypes
                    |> List.map
                        (\field ->
                            concreteTypeToMetaType ir varToMeta field.tpe
                                |> Counter.map (Tuple.pair field.name)
                        )
                    |> Counter.concat
                    |> Counter.map Dict.fromList
                )

        Type.Function _ argType returnType ->
            Counter.map2 metaFun
                (concreteTypeToMetaType ir varToMeta argType)
                (concreteTypeToMetaType ir varToMeta returnType)

        Type.Unit _ ->
            Counter.ignore metaUnit


ctorToMetaType : IR -> FQName -> List Name -> List (Type ()) -> Counter MetaType
ctorToMetaType ir ctorFQName paramNames ctorArgs =
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
    in
    allVariables
        |> concreteVarsToMetaVars
        |> Counter.andThen
            (\varToMeta ->
                let
                    recurse : List (Type ()) -> Counter MetaType
                    recurse cargs =
                        case cargs of
                            [] ->
                                Counter.next
                                    (\counter ->
                                        metaRef ctorFQName
                                            (paramNames
                                                |> List.map
                                                    (\paramName ->
                                                        varToMeta
                                                            |> Dict.get paramName
                                                            -- this should never happen
                                                            |> Maybe.withDefault (MetaType.variableByIndex counter)
                                                            |> metaVar
                                                    )
                                            )
                                    )

                            firstCtorArg :: restOfCtorArgs ->
                                Counter.map2 metaFun
                                    (concreteTypeToMetaType ir varToMeta firstCtorArg)
                                    (recurse restOfCtorArgs)
                in
                recurse ctorArgs
            )


valueSpecToMetaType : IR -> Value.Specification () -> Counter MetaType
valueSpecToMetaType ir valueSpec =
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
    in
    functionType
        |> Type.collectVariables
        |> concreteVarsToMetaVars
        |> Counter.andThen (\varToMeta -> concreteTypeToMetaType ir varToMeta functionType)


concreteVarsToMetaVars : Set Name -> Counter (Dict Name Variable)
concreteVarsToMetaVars variables =
    variables
        |> Set.toList
        |> List.map
            (\varName ->
                Counter.next
                    (\counter ->
                        ( varName, MetaType.variableByIndex counter )
                    )
            )
        |> Counter.concat
        |> Counter.map Dict.fromList
