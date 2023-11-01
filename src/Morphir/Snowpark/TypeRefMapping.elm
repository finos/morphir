module Morphir.Snowpark.TypeRefMapping exposing (generateRecordTypeWrapperExpression, mapTypeReference)

import Morphir.IR.Name as Name
import Morphir.IR.Type exposing (Type(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.Snowpark.MappingContext exposing (MappingContextInfo, isAliasedBasicType, isBasicType, isCandidateForDataFrame, isDataFrameFriendlyType)
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.MappingContext exposing (getLocalVariableIfDataFrameReference)
import Morphir.Snowpark.Utils exposing (tryAlternatives)
import Morphir.IR.Type as Type

checkDataFrameCase : Type () -> MappingContextInfo () -> Maybe Scala.Type
checkDataFrameCase typeReference ctx =
    if isCandidateForDataFrame typeReference ctx then
        Just <| typeRefForSnowparkType "DataFrame"
    else
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

mapTypeReference : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReference typeReference ctx =
   tryAlternatives [ (\_ -> checkDataFrameCase typeReference ctx)
                   , (\_ -> checkForColumnCase typeReference ctx)
                   , (\_ -> checkDefaultCase typeReference ctx)
                   , (\_ -> checkForListOfSimpleTypes typeReference ctx) ]
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