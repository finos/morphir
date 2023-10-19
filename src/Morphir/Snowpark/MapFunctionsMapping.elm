module Morphir.Snowpark.MapFunctionsMapping exposing (..)
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.IR.Type exposing (Type)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)


mapFunctionsMapping : Value ta (Type ()) -> (Value ta (Type ()) -> ValueMappingContext -> Scala.Value) -> ValueMappingContext -> Scala.Value
mapFunctionsMapping value mapValue ctx =
    case value of
        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "member" ] )) predicate) sourceRelation ->
            let
                variable = mapValue predicate ctx
                applySequence = mapValue sourceRelation ctx
            in
            Scala.Apply (Scala.Select variable "in") [ Scala.ArgValue Nothing applySequence ]
        _ ->
            Scala.Literal (Scala.StringLit "To Do")