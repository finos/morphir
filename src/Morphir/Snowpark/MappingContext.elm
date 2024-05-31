module Morphir.Snowpark.MappingContext exposing
    ( FunctionClassification(..)
    , GlobalDefinitionInformation
    , MappingContextInfo
    , ValueMappingContext
    , addLocalDefinitions
    , addReplacementForIdentifier
    , emptyContext
    , emptyValueMappingContext
    , getFieldInfoIfRecordType
    , getFunctionClassification
    , getLocalVariableIfDataFrameReference
    , getReplacementForIdentifier
    , isAliasedBasicType
    , isAnonymousRecordWithSimpleTypes
    , isBasicType
    , isCandidateForDataFrame
    , isDataFrameFriendlyType
    , isFunctionClassificationReturningDataFrameExpressions
    , isFunctionReceivingDataFrameExpressions
    , isFunctionReturningDataFrameExpressions
    , isListOfDataFrameFriendlyType
    , isLocalFunctionName
    , isLocalVariableDefinition
    , isRecordWithComplexTypes
    , isRecordWithSimpleTypes
    , isTypeAlias
    , isTypeRefToRecordWithComplexTypes
    , isTypeRefToRecordWithSimpleTypes
    , isUnionTypeRefWithParams
    , isUnionTypeRefWithoutParams
    , isUnionTypeWithParams
    , isUnionTypeWithoutParams
    , processDistributionModules
    , resolveTypeAlias
    , typeRefIsListOf
    )

{-| This module contains functions to collect information about type definitions in a distribution.
It classifies type definitions in the following kinds:

  - records with 'simple' or basic types (canditate to be treated as a dataframe)
  - records containing other records
  - Union types or Custom types with name-only constructors
  - Union types or Custom types with complex constructors
  - Builtin type aliases
    |

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Definition(..), Type(..))
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Customization exposing (CustomizationOptions)
import Morphir.Snowpark.Utils exposing (tryAlternatives)
import Set exposing (Set)


type TypeDefinitionClassification a
    = RecordWithSimpleTypes (List ( Name, Type a ))
    | RecordWithComplexTypes (List ( Name, Type a ))
    | UnionTypeWithoutParams
    | UnionTypeWithParams
    | TypeAlias (Type a)


type FunctionClassification
    = FromDataFramesToValues
    | FromDataFramesToDataFrames
    | FromDfValuesToDfValues
    | FromComplexValuesToDataFrames
    | FromComplexToValues
    | Unknown


type alias FunctionClassificationInformation =
    Dict FQName FunctionClassification


type alias MappingContextInfo a =
    Dict FQName (TypeClassificationState a)


type alias InlineValuesCollection =
    Dict FQName (Value.Definition () (Type ()))


type alias GlobalDefinitionInformation a =
    ( MappingContextInfo a, FunctionClassificationInformation, InlineValuesCollection )


type alias ValueMappingContext =
    { parameters : List Name
    , localDefinitions : Set Name
    , typesContextInfo : MappingContextInfo ()
    , inlinedIds : Dict Name Scala.Value
    , packagePath : Path.Path
    , dataFrameColumnsObjects : Dict FQName String
    , functionClassificationInfo : FunctionClassificationInformation
    , currentFunctionClassification : FunctionClassification
    , globalValuesToInline : Dict FQName.FQName (Value.Definition () (Type.Type ()))
    }


emptyValueMappingContext : ValueMappingContext
emptyValueMappingContext =
    { parameters = []
    , localDefinitions = Set.empty
    , inlinedIds = Dict.empty
    , typesContextInfo = emptyContext
    , packagePath = Path.fromString "default"
    , dataFrameColumnsObjects = Dict.empty
    , functionClassificationInfo = Dict.empty
    , currentFunctionClassification = Unknown
    , globalValuesToInline = Dict.empty
    }


isLocalVariableDefinition : Name -> ValueMappingContext -> Bool
isLocalVariableDefinition name ctx =
    Set.member name ctx.localDefinitions


addLocalDefinitions : List Name -> ValueMappingContext -> ValueMappingContext
addLocalDefinitions names ctx =
    { ctx | localDefinitions = Set.union (Set.fromList names) ctx.localDefinitions }


isFunctionReturningDataFrameExpressions : FQName -> ValueMappingContext -> Bool
isFunctionReturningDataFrameExpressions name ctx =
    Dict.get name ctx.functionClassificationInfo
        |> Maybe.map isFunctionClassificationReturningDataFrameExpressions
        |> Maybe.withDefault False


isFunctionClassificationReturningDataFrameExpressions : FunctionClassification -> Bool
isFunctionClassificationReturningDataFrameExpressions classfication =
    case classfication of
        FromDfValuesToDfValues ->
            True

        _ ->
            False


isFunctionReceivingDataFrameExpressions : FQName -> ValueMappingContext -> Bool
isFunctionReceivingDataFrameExpressions name ctx =
    Dict.get name ctx.functionClassificationInfo
        |> Maybe.map isFunctionClassificationReceivingDataFrameExpressions
        |> Maybe.withDefault False


isFunctionClassificationReceivingDataFrameExpressions : FunctionClassification -> Bool
isFunctionClassificationReceivingDataFrameExpressions classfication =
    case classfication of
        FromDfValuesToDfValues ->
            True

        FromDataFramesToValues ->
            True

        FromDataFramesToDataFrames ->
            True

        _ ->
            False


getReplacementForIdentifier : Name -> ValueMappingContext -> Maybe Scala.Value
getReplacementForIdentifier name ctx =
    Dict.get name ctx.inlinedIds


addReplacementForIdentifier : Name -> Scala.Value -> ValueMappingContext -> ValueMappingContext
addReplacementForIdentifier name value ctx =
    let
        newReplacedIds =
            Dict.insert name value ctx.inlinedIds
    in
    { ctx | inlinedIds = newReplacedIds }


emptyContext : MappingContextInfo a
emptyContext =
    Dict.empty


isLocalFunctionName : FQName -> ValueMappingContext -> Bool
isLocalFunctionName name ctx =
    FQName.getPackagePath name == ctx.packagePath


isRecordWithSimpleTypes : FQName -> MappingContextInfo () -> Bool
isRecordWithSimpleTypes name ctx =
    case Dict.get name ctx of
        Just (TypeClassified (RecordWithSimpleTypes _)) ->
            True

        _ ->
            False


isTypeRefToRecordWithSimpleTypes : Type () -> MappingContextInfo () -> Bool
isTypeRefToRecordWithSimpleTypes tpe ctx =
    typeRefNamePredicate tpe isRecordWithSimpleTypes ctx


isTypeRefToRecordWithComplexTypes : Type a -> MappingContextInfo a -> Bool
isTypeRefToRecordWithComplexTypes tpe ctx =
    typeRefNamePredicate tpe isRecordWithComplexTypes ctx


isRecordWithComplexTypes : FQName -> MappingContextInfo a -> Bool
isRecordWithComplexTypes name ctx =
    case Dict.get name ctx of
        Just (TypeClassified (RecordWithComplexTypes _)) ->
            True

        _ ->
            False


isUnionTypeWithoutParams : FQName -> MappingContextInfo a -> Bool
isUnionTypeWithoutParams name ctx =
    case Dict.get name ctx of
        Just (TypeClassified UnionTypeWithoutParams) ->
            True

        _ ->
            False


typeRefNamePredicate : Type a -> (FQName -> MappingContextInfo a -> Bool) -> MappingContextInfo a -> Bool
typeRefNamePredicate tpe predicateToCheckOnName ctx =
    case tpe of
        Type.Reference _ name _ ->
            predicateToCheckOnName name ctx

        _ ->
            False


isUnionTypeRefWithoutParams : Type a -> MappingContextInfo a -> Bool
isUnionTypeRefWithoutParams tpe ctx =
    typeRefNamePredicate tpe isUnionTypeWithoutParams ctx


isUnionTypeRefWithParams : Type a -> MappingContextInfo a -> Bool
isUnionTypeRefWithParams tpe ctx =
    typeRefNamePredicate tpe isUnionTypeWithParams ctx


isUnionTypeWithParams : FQName -> MappingContextInfo a -> Bool
isUnionTypeWithParams name ctx =
    case Dict.get name ctx of
        Just (TypeClassified UnionTypeWithParams) ->
            True

        _ ->
            False


isTypeAlias : FQName -> MappingContextInfo a -> Bool
isTypeAlias name ctx =
    case Dict.get name ctx of
        Just (TypeClassified (TypeAlias _)) ->
            True

        _ ->
            False


resolveTypeAlias : FQName -> MappingContextInfo a -> Maybe (Type a)
resolveTypeAlias name ctx =
    case Dict.get name ctx of
        Just (TypeClassified (TypeAlias t)) ->
            Just t

        _ ->
            Nothing


isCandidateForDataFrame : Type () -> MappingContextInfo () -> Bool
isCandidateForDataFrame typeRef ctx =
    case typeRef of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ Type.Reference _ itemTypeName [] ] ->
            isRecordWithSimpleTypes itemTypeName ctx

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ Type.Record _ fields ] ->
            fields
                |> List.all (\{ tpe } -> isDataFrameFriendlyType tpe ctx)

        Type.Reference _ name [] ->
            resolveTypeAlias name ctx
                |> Maybe.map (\resolvedType -> isCandidateForDataFrame resolvedType ctx)
                |> Maybe.withDefault False

        _ ->
            False


isListOfDataFrameFriendlyType : Type () -> MappingContextInfo () -> Bool
isListOfDataFrameFriendlyType typeRef ctx =
    case typeRef of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ tpe ] ->
            isDataFrameFriendlyType tpe ctx

        _ ->
            False


getLocalVariableIfDataFrameReference : Type.Type () -> ValueMappingContext -> Maybe String
getLocalVariableIfDataFrameReference tpe ctx =
    case tpe of
        Type.Reference _ typeName _ ->
            Dict.get typeName ctx.dataFrameColumnsObjects

        _ ->
            Nothing


isAnonymousRecordWithSimpleTypes : Type.Type () -> MappingContextInfo () -> Bool
isAnonymousRecordWithSimpleTypes tpe ctx =
    case tpe of
        Type.Record _ fields ->
            List.all (\field -> isDataFrameFriendlyType field.tpe ctx) fields

        _ ->
            False


type TypeClassificationState a
    = TypeClassified (TypeDefinitionClassification a)
    | TypeWithPendingClassification (Maybe (Type a))
    | TypeNotClassified


classifyType : Type.Definition () -> MappingContextInfo () -> TypeClassificationState ()
classifyType typeDefinition ctx =
    case typeDefinition of
        Type.TypeAliasDefinition _ t ->
            classifyActualType t ctx

        Type.CustomTypeDefinition _ { value } ->
            let
                zeroArgConstructors =
                    value
                        |> Dict.values
                        |> List.all (\args -> 0 == List.length args)
            in
            if zeroArgConstructors then
                TypeClassified UnionTypeWithoutParams

            else
                TypeClassified UnionTypeWithParams


isBasicType : Type a -> Bool
isBasicType tpe =
    case tpe of
        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], _ ) _ ->
            True

        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], _ ) _ ->
            True

        _ ->
            False


isSdkType : Type a -> Bool
isSdkType tpe =
    case tpe of
        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], _, _ ) _ ->
            True

        _ ->
            False


isAliasedBasicType : Type a -> MappingContextInfo a -> Bool
isAliasedBasicType tpe ctx =
    case tpe of
        Type.Reference _ fqname [] ->
            Maybe.withDefault False (Dict.get fqname ctx |> Maybe.map isAliasedBasicTypeWithPendingClassification)

        _ ->
            False


isAliasedBasicTypeWithPendingClassification : TypeClassificationState a -> Bool
isAliasedBasicTypeWithPendingClassification transitoryTypeClassification =
    transitoryTypeClassification
        |> aliasedBasicTypeWithPendingClassification
        |> Maybe.map isBasicType
        |> Maybe.withDefault False


aliasedBasicTypeWithPendingClassification : TypeClassificationState a -> Maybe (Type a)
aliasedBasicTypeWithPendingClassification transitoryTypeClassification =
    case transitoryTypeClassification of
        TypeClassified (TypeAlias tpe) ->
            Just tpe

        _ ->
            Nothing


isUnionType : Type a -> MappingContextInfo a -> Bool
isUnionType tpe ctx =
    let
        isUnionTypePred =
            \t ->
                case t of
                    TypeClassified UnionTypeWithoutParams ->
                        True

                    TypeClassified UnionTypeWithParams ->
                        True

                    _ ->
                        False
    in
    case tpe of
        Reference _ name _ ->
            Dict.get name ctx
                |> Maybe.map isUnionTypePred
                |> Maybe.withDefault False

        _ ->
            False


isAliasOfBasicType : Type a -> MappingContextInfo a -> Bool
isAliasOfBasicType tpe ctx =
    case tpe of
        Reference _ name _ ->
            Dict.get name ctx
                |> Maybe.map isAliasedBasicTypeWithPendingClassification
                |> Maybe.withDefault False

        _ ->
            False


isAliasOfDataFrameFriendlyType : Type a -> MappingContextInfo a -> Bool
isAliasOfDataFrameFriendlyType tpe ctx =
    case tpe of
        Reference _ name _ ->
            Dict.get name ctx
                |> Maybe.map aliasedBasicTypeWithPendingClassification
                |> Maybe.withDefault Nothing
                |> Maybe.map (\x -> isDataFrameFriendlyType x ctx)
                |> Maybe.withDefault False

        _ ->
            False


typeRefIsMaybeOf : Type a -> (Type a -> Bool) -> Bool
typeRefIsMaybeOf tpe predicate =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ typeArg ] ->
            predicate typeArg

        _ ->
            False


typeRefIsListOf : Type a -> (Type a -> Bool) -> Bool
typeRefIsListOf tpe predicate =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ typeArg ] ->
            predicate typeArg

        _ ->
            False


isMaybeOfDataFrameFriendlyType : Type a -> MappingContextInfo a -> Bool
isMaybeOfDataFrameFriendlyType tpe ctx =
    typeRefIsMaybeOf tpe (\innerTpe -> isDataFrameFriendlyType innerTpe ctx)


isDataFrameFriendlyType : Type a -> MappingContextInfo a -> Bool
isDataFrameFriendlyType tpe ctx =
    isBasicType tpe
        || isUnionType tpe ctx
        || isAliasOfDataFrameFriendlyType tpe ctx
        || isMaybeOfDataFrameFriendlyType tpe ctx


getFieldInfoIfRecordType : Type a -> MappingContextInfo a -> Maybe (List ( Name, Type a ))
getFieldInfoIfRecordType tpe ctx =
    case tpe of
        Reference _ typeName _ ->
            case Dict.get typeName ctx of
                Just (TypeClassified (RecordWithSimpleTypes fieldInfo)) ->
                    Just fieldInfo

                Just (TypeClassified (RecordWithComplexTypes fieldInfo)) ->
                    Just fieldInfo

                _ ->
                    Nothing

        Record _ fields ->
            Just <| List.map (\field -> ( field.name, field.tpe )) fields

        _ ->
            Nothing


getFunctionClassification : FQName -> FunctionClassificationInformation -> FunctionClassification
getFunctionClassification fullName functionsInfo =
    Dict.get fullName functionsInfo
        |> Maybe.withDefault Unknown


classifyActualType : Type a -> MappingContextInfo a -> TypeClassificationState a
classifyActualType tpe ctx =
    case tpe of
        Record _ members ->
            if List.all (\t -> isDataFrameFriendlyType t.tpe ctx) members then
                TypeClassified (RecordWithSimpleTypes (members |> List.map (\field -> ( field.name, field.tpe ))))

            else
                TypeWithPendingClassification (Just tpe)

        Reference _ _ _ ->
            if
                isBasicType tpe
                    || isUnionType tpe ctx
                    || isAliasOfDataFrameFriendlyType tpe ctx
                    || isSdkType tpe
            then
                TypeClassified (TypeAlias tpe)

            else
                TypeWithPendingClassification (Just tpe)

        _ ->
            TypeNotClassified


simpleName packagePath modName name =
    FQName.fQName packagePath modName name


processFunctionDefinition : Value.Definition () (Type ()) -> MappingContextInfo () -> FunctionClassification
processFunctionDefinition definition ctx =
    let
        inputTypes =
            definition.inputTypes |> List.map (\( _, _, third ) -> third)
    in
    tryAlternatives
        [ \_ ->
            if
                List.all (\tpe -> isDataFrameFriendlyType tpe ctx) inputTypes
                    && isDataFrameFriendlyType definition.outputType ctx
            then
                Just FromDfValuesToDfValues

            else
                Nothing
        , \_ ->
            if
                List.all
                    (\tpe ->
                        isDataFrameFriendlyType tpe ctx
                            || isTypeRefToRecordWithSimpleTypes tpe ctx
                            || isTypeRefToRecordWithSimpleTypes tpe ctx
                            || typeRefIsMaybeOf tpe (\t -> isTypeRefToRecordWithSimpleTypes t ctx)
                    )
                    inputTypes
                    && (isDataFrameFriendlyType definition.outputType ctx
                            || isTypeRefToRecordWithSimpleTypes definition.outputType ctx
                            || typeRefIsMaybeOf definition.outputType (\t -> isTypeRefToRecordWithSimpleTypes t ctx || isAnonymousRecordWithSimpleTypes t ctx)
                       )
            then
                Just FromDfValuesToDfValues

            else
                Nothing
        , \_ ->
            if
                List.all
                    (\tpe ->
                        isDataFrameFriendlyType tpe ctx
                            || typeRefIsListOf tpe (\listElementType -> isDataFrameFriendlyType listElementType ctx)
                            || isTypeRefToRecordWithSimpleTypes tpe ctx
                    )
                    inputTypes
                    && typeRefIsListOf definition.outputType (\t -> isTypeRefToRecordWithSimpleTypes t ctx)
            then
                Just FromDfValuesToDfValues

            else
                Nothing
        , \_ ->
            if
                List.any (\tpe -> isCandidateForDataFrame tpe ctx) inputTypes
                    && not (List.any (\tpe -> isTypeRefToRecordWithComplexTypes tpe ctx) inputTypes)
                    && isDataFrameFriendlyType definition.outputType ctx
            then
                Just FromDataFramesToValues

            else
                Nothing
        , \_ ->
            if
                List.any (\tpe -> isCandidateForDataFrame tpe ctx) inputTypes
                    && not (List.any (\tpe -> isTypeRefToRecordWithComplexTypes tpe ctx) inputTypes)
                    && isCandidateForDataFrame definition.outputType ctx
            then
                Just FromDataFramesToDataFrames

            else
                Nothing
        , \_ ->
            if
                List.any (\tpe -> isTypeRefToRecordWithComplexTypes tpe ctx) inputTypes
                    && isCandidateForDataFrame definition.outputType ctx
            then
                Just FromComplexValuesToDataFrames

            else
                Nothing
        , \_ ->
            if List.any (\tpe -> isTypeRefToRecordWithComplexTypes tpe ctx) inputTypes then
                Just FromComplexToValues

            else
                Nothing
        ]
        |> Maybe.withDefault Unknown


processModuleDefinition : Package.PackageName -> ModuleName -> MappingContextInfo () -> AccessControlled (Module.Definition () (Type ())) -> MappingContextInfo ()
processModuleDefinition packagePath modulePath currentResult moduleDefinition =
    moduleDefinition.value.types
        |> Dict.toList
        |> List.map (\( name, acc ) -> ( name, acc.value.value ))
        |> List.map (\( name, typeDefinition ) -> ( simpleName packagePath modulePath name, classifyType typeDefinition currentResult ))
        |> Dict.fromList
        |> Dict.union currentResult


processSecondPassOnType : FQName -> TypeClassificationState () -> MappingContextInfo () -> MappingContextInfo ()
processSecondPassOnType name typeClassification ctx =
    case typeClassification of
        TypeClassified _ ->
            ctx

        TypeWithPendingClassification (Just tpe) ->
            case classifyActualType tpe ctx of
                TypeClassified newType ->
                    Dict.update name (\_ -> Just (TypeClassified newType)) ctx

                -- If we could not classify a record after the second pass classify it as 'complex'
                TypeWithPendingClassification (Just (Record _ members)) ->
                    Dict.update name (\_ -> Just (TypeClassified (RecordWithComplexTypes (members |> List.map (\field -> ( field.name, field.tpe )))))) ctx

                _ ->
                    ctx

        _ ->
            ctx


processDistributionModules : Package.PackageName -> Package.Definition () (Type ()) -> CustomizationOptions -> GlobalDefinitionInformation ()
processDistributionModules packagePath package customizationOptions =
    let
        moduleList =
            package.modules
                |> Dict.toList

        firstPass =
            moduleList
                |> List.foldr
                    (\( modName, modDef ) curretnResult -> processModuleDefinition packagePath modName curretnResult modDef)
                    Dict.empty

        secondPass =
            firstPass
                |> Dict.foldr (\key value result -> processSecondPassOnType key value result) firstPass

        functionsClassifed =
            moduleList
                |> List.concatMap
                    (\( modName, modDef ) ->
                        modDef.value.values
                            |> Dict.toList
                            |> List.map (\( valueName, value ) -> ( modName, valueName, value.value.value ))
                    )
                |> List.filter (\( modName, valueName, value ) -> 0 < List.length value.inputTypes)
                |> List.foldl
                    (\( modName, valueName, value ) current ->
                        let
                            fullFunctionName =
                                FQName.fQName packagePath modName valueName

                            classfication =
                                processFunctionDefinition value secondPass
                        in
                        Dict.insert fullFunctionName classfication current
                    )
                    Dict.empty

        valuesToInline =
            collectValuesToInline customizationOptions.functionsToInline package.modules
    in
    ( secondPass, functionsClassifed, valuesToInline )


collectValuesToInline : Set FQName -> Dict ModuleName (AccessControlled (Module.Definition () (Type ()))) -> Dict FQName (Value.Definition () (Type ()))
collectValuesToInline namesToInline modules =
    collectingValuesToInline (Set.toList namesToInline) modules Dict.empty


collectingValuesToInline : List FQName -> Dict ModuleName (AccessControlled (Module.Definition () (Type ()))) -> Dict FQName (Value.Definition () (Type ())) -> Dict FQName (Value.Definition () (Type ()))
collectingValuesToInline namesToInline modules current =
    case namesToInline of
        first :: rest ->
            let
                newDict =
                    case Dict.get (FQName.getModulePath first) modules of
                        Just mod ->
                            case Dict.get (FQName.getLocalName first) mod.value.values of
                                Just { value } ->
                                    Dict.insert first value.value current

                                _ ->
                                    current

                        _ ->
                            current
            in
            collectingValuesToInline rest modules newDict

        _ ->
            current
