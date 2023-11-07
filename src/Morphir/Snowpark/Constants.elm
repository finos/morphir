module Morphir.Snowpark.Constants exposing (..)
import Morphir.Scala.AST as Scala
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..))
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)

snowflakeNamespace : List String
snowflakeNamespace = ["com", "snowflake", "snowpark"]

functionsNamespace : List String
functionsNamespace = snowflakeNamespace ++  ["functions"]

applySnowparkFunc : String -> List Scala.Value -> Scala.Value
applySnowparkFunc name args =
    Scala.Apply 
        (Scala.Ref functionsNamespace name)
        (args |> List.map (\v -> Scala.ArgValue Nothing v))


typeRefForSnowparkType : String -> Scala.Type
typeRefForSnowparkType typeName =
    (Scala.TypeRef snowflakeNamespace typeName)

type alias MapValueType ta = ValueIR.Value ta (TypeIR.Type ()) -> ValueMappingContext -> Scala.Value

type alias VariableInformation = (List Scala.Value, List (String, Scala.Value))