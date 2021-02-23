module Morphir.Type.MetaTypeMapping exposing (..)

import Dict exposing (Dict)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable)
import Morphir.Type.SolutionMap as SolutionMap exposing (SolutionMap)
import Set exposing (Set)


type LookupError
    = CouldNotFindConstructor FQName
    | CouldNotFindValue FQName
    | CouldNotFindAlias FQName
    | ExpectedAlias FQName


lookupConstructor : Variable -> IR -> FQName -> Result LookupError MetaType
lookupConstructor baseVar ir (( packageName, moduleName, ctorName ) as ctorFQN) =
    ir
        |> IR.lookupTypeConstructor ctorFQN
        |> Maybe.map
            (\( _, paramNames, ctorArgs ) ->
                ctorToMetaType baseVar ir (MetaRef ( packageName, moduleName, ctorName )) paramNames (ctorArgs |> List.map Tuple.second)
            )
        |> Result.fromMaybe (CouldNotFindConstructor ctorFQN)


lookupValue : Variable -> IR -> FQName -> Result LookupError MetaType
lookupValue baseVar ir valueFQN =
    ir
        |> IR.lookupValueSpecification valueFQN
        |> Maybe.map (valueSpecToMetaType baseVar ir)
        |> Result.fromMaybe (CouldNotFindValue valueFQN)


lookupAliasedType : Variable -> IR -> FQName -> Result LookupError (Type ())
lookupAliasedType baseVar ir typeFQN =
    ir
        |> IR.lookupTypeSpecification typeFQN
        |> Result.fromMaybe (CouldNotFindAlias typeFQN)
        |> Result.andThen
            (\typeSpec ->
                case typeSpec of
                    Type.TypeAliasSpecification paramNames tpe ->
                        Ok tpe

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

        MetaTuple metaElems ->
            Type.Tuple ()
                (metaElems
                    |> List.map (metaTypeToConcreteType solutionMap)
                )

        MetaRecord extends metaFields ->
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

        MetaApply _ _ ->
            let
                uncurry mt =
                    case mt of
                        MetaApply mf ma ->
                            let
                                ( f, args ) =
                                    uncurry mf
                            in
                            ( f, args ++ [ ma ] )

                        _ ->
                            ( mt, [] )

                ( metaFun, metaArgs ) =
                    uncurry metaType
            in
            case metaFun of
                MetaRef fQName ->
                    metaArgs
                        |> List.map (metaTypeToConcreteType solutionMap)
                        |> Type.Reference () fQName

                MetaAlias alias _ ->
                    metaArgs
                        |> List.map (metaTypeToConcreteType solutionMap)
                        |> Type.Reference () alias

                other ->
                    metaTypeToConcreteType solutionMap other

        MetaFun argType returnType ->
            Type.Function ()
                (metaTypeToConcreteType solutionMap argType)
                (metaTypeToConcreteType solutionMap returnType)

        MetaRef fQName ->
            Type.Reference () fQName []

        MetaUnit ->
            Type.Unit ()

        MetaAlias alias _ ->
            Type.Reference () alias []


concreteTypeToMetaType : Variable -> IR -> Dict Name Variable -> Type () -> MetaType
concreteTypeToMetaType baseVar ir varToMeta tpe =
    case tpe of
        Type.Variable _ varName ->
            varToMeta
                |> Dict.get varName
                -- this should never happen
                |> Maybe.withDefault baseVar
                |> MetaVar

        Type.Reference _ fQName args ->
            let
                resolveAliases : FQName -> MetaType
                resolveAliases fqn =
                    lookupAliasedType baseVar ir fqn
                        |> Result.map (concreteTypeToMetaType baseVar ir varToMeta >> MetaAlias fqn)
                        |> Result.withDefault (MetaRef fqn)

                curry : List (Type ()) -> MetaType
                curry argsReversed =
                    case argsReversed of
                        [] ->
                            resolveAliases fQName

                        lastArg :: initArgsReversed ->
                            MetaApply
                                (curry initArgsReversed)
                                (concreteTypeToMetaType baseVar ir varToMeta lastArg)
            in
            curry (args |> List.reverse)

        Type.Tuple _ elemTypes ->
            MetaTuple
                (elemTypes
                    |> List.map (concreteTypeToMetaType baseVar ir varToMeta)
                )

        Type.Record _ fieldTypes ->
            MetaRecord Nothing
                (fieldTypes
                    |> List.map
                        (\field ->
                            ( field.name, concreteTypeToMetaType baseVar ir varToMeta field.tpe )
                        )
                    |> Dict.fromList
                )

        Type.ExtensibleRecord _ subjectName fieldTypes ->
            MetaRecord
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
            MetaFun
                (concreteTypeToMetaType baseVar ir varToMeta argType)
                (concreteTypeToMetaType baseVar ir varToMeta returnType)

        Type.Unit _ ->
            MetaUnit


ctorToMetaType : Variable -> IR -> MetaType -> List Name -> List (Type ()) -> MetaType
ctorToMetaType baseVar ir baseType paramNames ctorArgs =
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
                    paramNames
                        |> List.foldl
                            (\paramName metaTypeSoFar ->
                                MetaApply metaTypeSoFar
                                    (varToMeta
                                        |> Dict.get paramName
                                        -- this should never happen
                                        |> Maybe.withDefault baseVar
                                        |> MetaVar
                                    )
                            )
                            baseType

                firstCtorArg :: restOfCtorArgs ->
                    MetaFun
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
