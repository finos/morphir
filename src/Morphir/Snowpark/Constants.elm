module Morphir.Snowpark.Constants exposing (..)
import Morphir.Scala.AST as Scala

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