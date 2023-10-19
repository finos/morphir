module Morphir.Snowpark.TypeRefMapping exposing (..)
import Morphir.Snowpark.MappingContext exposing (MappingContextInfo)
import Morphir.Scala.AST as Scala
import Morphir.IR.Type exposing (Type(..))
import Morphir.Snowpark.MappingContext exposing (isCandidateForDataFrame)
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.Snowpark.MappingContext exposing (isBasicType)


mapTypeReference : (Type ()) -> MappingContextInfo () -> Scala.Type
mapTypeReference typeReference ctx =   
   if isCandidateForDataFrame typeReference ctx then
        typeRefForSnowparkType "DataFrame"  
   else 
     if isBasicType typeReference then
        typeRefForSnowparkType "Column"
     else
        Scala.TypeVar "TypeNotConverted"
