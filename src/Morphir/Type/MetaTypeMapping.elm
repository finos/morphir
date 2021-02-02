module Morphir.Type.MetaTypeMapping exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable)
import Morphir.Type.SolutionMap as SolutionMap exposing (SolutionMap)
import Set exposing (Set)


type alias References =
    Dict PackageName (Package.Specification ())


type LookupError
    = CouldNotFindConstructor FQName
    | CouldNotFindValue FQName
    | CouldNotFindAlias FQName
    | ExpectedAlias FQName


lookupConstructor : Variable -> References -> FQName -> Result LookupError MetaType
lookupConstructor baseVar refs (( packageName, moduleName, localName ) as fQName) =
    refs
        |> Dict.get packageName
        |> Maybe.andThen (.modules >> Dict.get moduleName)
        |> Maybe.andThen
            (\moduleSpec ->
                moduleSpec.types
                    |> Dict.toList
                    |> List.concatMap
                        (\( typeName, typeSpec ) ->
                            case typeSpec.value of
                                Type.CustomTypeSpecification paramNames ctors ->
                                    ctors
                                        |> List.filterMap
                                            (\(Type.Constructor ctorName ctorArgs) ->
                                                if ctorName == localName then
                                                    Just (ctorToMetaType baseVar refs (MetaRef ( packageName, moduleName, typeName )) paramNames (ctorArgs |> List.map Tuple.second))

                                                else
                                                    Nothing
                                            )

                                _ ->
                                    []
                        )
                    |> List.head
            )
        |> Result.fromMaybe (CouldNotFindConstructor fQName)


lookupValue : Variable -> References -> FQName -> Result LookupError MetaType
lookupValue baseVar refs (( packageName, moduleName, localName ) as fQName) =
    refs
        |> Dict.get packageName
        |> Maybe.andThen (.modules >> Dict.get moduleName)
        |> Maybe.andThen (.values >> Dict.get localName)
        |> Maybe.map (valueSpecToMetaType baseVar refs)
        |> Result.fromMaybe (CouldNotFindValue fQName)


lookupAliasedType : Variable -> References -> FQName -> Result LookupError (Type ())
lookupAliasedType baseVar refs (( packageName, moduleName, localName ) as fQName) =
    refs
        |> Dict.get packageName
        |> Maybe.andThen (.modules >> Dict.get moduleName)
        |> Maybe.andThen (.types >> Dict.get localName)
        |> Result.fromMaybe (CouldNotFindAlias fQName)
        |> Result.andThen
            (\typeSpec ->
                case typeSpec.value of
                    Type.TypeAliasSpecification paramNames tpe ->
                        Ok tpe

                    _ ->
                        Err (ExpectedAlias fQName)
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


concreteTypeToMetaType : Variable -> References -> Dict Name Variable -> Type () -> MetaType
concreteTypeToMetaType baseVar refs varToMeta tpe =
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
                    lookupAliasedType baseVar refs fqn
                        |> Result.map (concreteTypeToMetaType baseVar refs varToMeta >> MetaAlias fqn)
                        |> Result.withDefault (MetaRef fqn)

                curry : List (Type ()) -> MetaType
                curry argsReversed =
                    case argsReversed of
                        [] ->
                            resolveAliases fQName

                        lastArg :: initArgsReversed ->
                            MetaApply
                                (curry initArgsReversed)
                                (concreteTypeToMetaType baseVar refs varToMeta lastArg)
            in
            curry (args |> List.reverse)

        Type.Tuple _ elemTypes ->
            MetaTuple
                (elemTypes
                    |> List.map (concreteTypeToMetaType baseVar refs varToMeta)
                )

        Type.Record _ fieldTypes ->
            MetaRecord Nothing
                (fieldTypes
                    |> List.map
                        (\field ->
                            ( field.name, concreteTypeToMetaType baseVar refs varToMeta field.tpe )
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
                            ( field.name, concreteTypeToMetaType baseVar refs varToMeta field.tpe )
                        )
                    |> Dict.fromList
                )

        Type.Function _ argType returnType ->
            MetaFun
                (concreteTypeToMetaType baseVar refs varToMeta argType)
                (concreteTypeToMetaType baseVar refs varToMeta returnType)

        Type.Unit _ ->
            MetaUnit


ctorToMetaType : Variable -> References -> MetaType -> List Name -> List (Type ()) -> MetaType
ctorToMetaType baseVar refs baseType paramNames ctorArgs =
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
                        (concreteTypeToMetaType baseVar refs varToMeta firstCtorArg)
                        (recurse restOfCtorArgs)
    in
    recurse ctorArgs


valueSpecToMetaType : Variable -> References -> Value.Specification () -> MetaType
valueSpecToMetaType baseVar refs valueSpec =
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
    concreteTypeToMetaType baseVar refs varToMeta functionType


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
