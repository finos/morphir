module Morphir.Snowpark.TypeRefMapping exposing (generateRecordTypeWrapperExpression, mapTypeReference, mapFunctionReturnType, generateCastIfPossible)

import Morphir.IR.Name as Name
import Morphir.IR.Type exposing (Type(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.Snowpark.MappingContext as MappingContextMod
                 exposing (MappingContextInfo
                          , FunctionClassification
                          , isAliasedBasicType
                          , isBasicType
                          , isCandidateForDataFrame
                          , isDataFrameFriendlyType
                          , isTypeRefToRecordWithComplexTypes )
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.MappingContext exposing (getLocalVariableIfDataFrameReference)
import Morphir.Snowpark.Utils exposing (tryAlternatives)
import Morphir.IR.Type as Type
import Morphir.Snowpark.MappingContext exposing (GlobalDefinitionInformation)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.ReferenceUtils exposing (scalaPathToModule)
import Morphir.Snowpark.MappingContext exposing (isTypeAlias)
import Morphir.Snowpark.MappingContext exposing (resolveTypeAlias)
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Scala.Feature.Codec exposing (typeRef)


checkDataFrameCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkDataFrameCase typeReference ctx =
    if isCandidateForDataFrame typeReference ctx then
        Just <| typeRefForSnowparkType "DataFrame"
    else
        Nothing


checkComplexRecordCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkComplexRecordCase typeReference ctx =
    if isTypeRefToRecordWithComplexTypes typeReference ctx then
        case typeReference of
            Type.Reference _ fullName  [] ->
                Just <| Scala.TypeRef (scalaPathToModule fullName) (fullName |> FQName.getLocalName |> Name.toTitleCase)
            _ ->
                Nothing
    else
        Nothing

checkDataFrameCaseToArray : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkDataFrameCaseToArray typeReference ctx =
    if isCandidateForDataFrame typeReference ctx then
        Just <| typeRefForSnowparkType "Column"
    else
        Nothing

checkForFunctionTypeCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForFunctionTypeCase typeReference ctx =
    case typeReference of
        Type.Function _ fromType toType ->
            let
                convertedFrom = mapTypeReferenceForDataFrameOperations fromType ctx
                convertedTo =  mapTypeReferenceForDataFrameOperations toType ctx
            in
            Just <| Scala.FunctionType convertedFrom convertedTo
        _ ->
            Nothing

checkForColumnCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForColumnCase typeReference ctx =
    if isBasicType typeReference || 
       isAliasedBasicType typeReference ctx ||
       isDataFrameFriendlyType typeReference ctx ||
       isMaybeWithGenericType typeReference then
        Just <| typeRefForSnowparkType "Column"
    else
        Nothing

checkDefaultCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkDefaultCase typeReference ctx =
    let
        nameInfo =
            isTypeReferenceToSimpleTypesRecord typeReference ctx
        typeNameInfo =
            Maybe.map
                (\( typePath, simpleTypeName ) -> Just (Scala.TypeRef typePath (simpleTypeName |> Name.toTitleCase)))
                nameInfo
    in
    typeNameInfo |> Maybe.withDefault Nothing


mapFunctionReturnType : Type () -> FunctionClassification -> MappingContextInfo () -> Scala.Type
mapFunctionReturnType typeReference currentFunctionClassification ctx =
    case currentFunctionClassification of
        MappingContextMod.FromDataFramesToValues -> 
            mapTypeReferenceToBuiltinTypes typeReference ctx
        MappingContextMod.FromComplexToValues -> 
            mapTypeReferenceToBuiltinTypes typeReference ctx
        _ ->
             mapTypeReference typeReference currentFunctionClassification ctx

mapTypeReference : Type () -> FunctionClassification -> MappingContextInfo () -> Scala.Type
mapTypeReference typeReference currentFunctionClassification ctx =
    case currentFunctionClassification of
        MappingContextMod.FromDfValuesToDfValues -> mapTypeReferenceForColumnOperations typeReference ctx
        _ -> mapTypeReferenceForDataFrameOperations typeReference ctx
    

mapTypeReferenceForColumnOperations : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReferenceForColumnOperations typeReference  ctx =
   tryAlternatives [ (\_ -> checkDataFrameCaseToArray typeReference ctx)
                   , (\_ -> checkForColumnCase typeReference ctx)
                   , (\_ -> checkDefaultCase typeReference ctx)
                   , (\_ -> checkForListOfSimpleTypes typeReference ctx)
                   , (\_ -> checkComplexRecordCase typeReference ctx) ]
    |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")

mapTypeReferenceForDataFrameOperations : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReferenceForDataFrameOperations typeReference  ctx =
   tryAlternatives [ (\_ -> checkDataFrameCase typeReference ctx)
                   , (\_ -> checkForColumnCase typeReference ctx)
                   , (\_ -> checkDefaultCase typeReference ctx)
                   , (\_ -> checkForListOfSimpleTypes typeReference ctx)
                   , (\_ -> checkComplexRecordCase typeReference ctx)
                   , (\_ -> checkForFunctionTypeCase typeReference ctx) ]
    |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")

generateRecordTypeWrapperExpression : Type () -> ValueMappingContext -> Maybe Scala.Value
generateRecordTypeWrapperExpression typeReference ctx =
   getLocalVariableIfDataFrameReference typeReference ctx
         |> Maybe.map Scala.Variable

isMaybeWithGenericType : Type () -> Bool
isMaybeWithGenericType tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] )  [_] ->
            True
        _ ->
            False

checkForListOfSimpleTypes : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkForListOfSimpleTypes typeReference ctx =
    if isListOfSimpleType typeReference ctx then
        Just <| Scala.TypeApply (Scala.TypeRef [] "Seq") [typeRefForSnowparkType "Column"]
    else
        Nothing

isListOfSimpleType : Type () -> MappingContextInfo () -> Bool
isListOfSimpleType tpe ctx =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] )  [ elementType ] ->
            isDataFrameFriendlyType elementType ctx
        _ ->
            False

mapTypeReferenceToBuiltinTypes : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReferenceToBuiltinTypes tpe ctx =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            Scala.TypeVar "Double"
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            Scala.TypeVar "Int"
        Type.Reference _ fullTypeName [] ->
            if isTypeAlias fullTypeName ctx then
                resolveTypeAlias fullTypeName ctx
                    |> Maybe.map (\t -> mapTypeReferenceToBuiltinTypes t ctx)
                    |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")
            else
                Scala.TypeVar "TypeNotConverted"
        _ ->
            Scala.TypeVar "TypeNotConverted"


generateCastIfPossible : ValueMappingContext -> Type () -> Scala.Value -> Scala.Value
generateCastIfPossible ctx tpe value  =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            applySnowparkFunc "as_double" [value]
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            applySnowparkFunc "as_integer" [value]
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            applySnowparkFunc "as_char" [value]
        Type.Reference _ fullName [] ->
            if isTypeAlias fullName ctx.typesContextInfo then
                resolveTypeAlias fullName ctx.typesContextInfo
                    |> Maybe.map (\t -> generateCastIfPossible ctx t value)
                    |> Maybe.withDefault value
            else
                value
        _ ->
            value