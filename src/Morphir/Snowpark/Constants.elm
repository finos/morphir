module Morphir.Snowpark.Constants exposing (..)
import Morphir.Scala.AST as Scala

functionsNamespace : List String
functionsNamespace = ["com", "snowpark", "functions"]

applySnowparkFunc : String -> List Scala.Value -> Scala.Value
applySnowparkFunc name args =
    Scala.Apply 
        (Scala.Ref functionsNamespace name)
        (args |> List.map (\v -> Scala.ArgValue Nothing v))