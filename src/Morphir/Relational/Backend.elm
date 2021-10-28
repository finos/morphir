module Morphir.Relational.Backend exposing (..)

import Morphir.IR.Value as Value exposing (TypedValue)
import Morphir.Relational.IR exposing (Relation(..))


type Error
    = Unhandled


mapFunctionBody : TypedValue -> Result Error Relation
mapFunctionBody body =
    mapValue body


mapValue : TypedValue -> Result Error Relation
mapValue value =
    case value of
        Value.Variable _ varName ->
            Ok (From varName)

        Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "filter" ] )) predicate) sourceRelation ->
            mapValue sourceRelation
                |> Result.map
                    (\source ->
                        Where predicate source
                    )

        other ->
            let
                _ =
                    Debug.log "Relational.Backend.mapValue unhandled" other
            in
            Err Unhandled
