module Morphir.Snowpark.TypeRefMapping exposing (generateRecordTypeWrapperExpression, mapTypeReference)

import Morphir.IR.Name as Name
import Morphir.IR.Type exposing (Type(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.Snowpark.MappingContext exposing (MappingContextInfo, isAliasedBasicType, isBasicType, isCandidateForDataFrame, isDataFrameFriendlyType)
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.MappingContext exposing (getLocalVariableIfDataFrameReference)


mapTypeReference : Type () -> MappingContextInfo () -> Scala.Type
mapTypeReference typeReference ctx =
    if isCandidateForDataFrame typeReference ctx then
        typeRefForSnowparkType "DataFrame"

    else if isBasicType typeReference || isAliasedBasicType typeReference ctx || isDataFrameFriendlyType typeReference ctx then
        typeRefForSnowparkType "Column"

    else
        let
            nameInfo =
                isTypeReferenceToSimpleTypesRecord typeReference ctx

            typeNameInfo =
                Maybe.map
                    (\( typePath, simpleTypeName ) -> Just (Scala.TypeRef typePath (simpleTypeName |> Name.toTitleCase)))
                    nameInfo
        in
        typeNameInfo
            |> Maybe.withDefault Nothing
            |> Maybe.withDefault (Scala.TypeVar "TypeNotConverted")


generateRecordTypeWrapperExpression : Type () -> ValueMappingContext -> Maybe Scala.Value
generateRecordTypeWrapperExpression typeReference ctx =
   getLocalVariableIfDataFrameReference typeReference ctx
         |> Maybe.map Scala.Variable
