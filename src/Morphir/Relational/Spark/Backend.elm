module Morphir.Relational.Spark.Backend exposing (..)

import Morphir.IR.Value as Value exposing (Value)
import Morphir.Relational.IR exposing (Relation(..))


type Error
    = Unhandled


mapFunctionBody : Value ta va -> Result Error Relation
mapFunctionBody body =
    mapValue body


mapValue : Value ta va -> Result Error Relation
mapValue value =
    case value of
        Value.Variable _ varName ->
            Ok (From varName)

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "filter" ] )) predicate) sourceRelation ->
            mapValue sourceRelation
                |> Result.map
                    (\source ->
                        Where (Value.toRawValue predicate) source
                    )

        _ ->
            Err Unhandled
