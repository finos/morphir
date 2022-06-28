module Morphir.Relational.Backend exposing (..)

import Dict
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as V exposing (TypedValue)
import Morphir.Relational.IR as R exposing (Relation(..))


type Error
    = UnhandledValue TypedValue
    | UnknownValueReturnedByMapFunction TypedValue


mapFunctionBody : TypedValue -> Result Error Relation
mapFunctionBody body =
    mapValue body


mapValue : TypedValue -> Result Error Relation
mapValue value =
    case value of
        V.Variable _ varName ->
            Ok (R.From varName)

        V.Apply _ (V.Apply _ (V.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "filter" ] )) predicate) sourceRelation ->
            mapValue sourceRelation
                |> Result.map
                    (\source ->
                        R.Where predicate source
                    )

        V.Apply _ (V.Apply _ (V.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) (V.Lambda _ argPattern mapping)) sourceRelation ->
            case mapping of
                V.Record _ fields ->
                    mapValue sourceRelation
                        |> Result.map
                            (\source ->
                                R.Select (Dict.toList fields) source
                            )

                other ->
                    Err (UnknownValueReturnedByMapFunction other)

        other ->
            let
                _ =
                    Debug.log "Relational.Backend.mapValue unhandled" other
            in
            Err (UnhandledValue other)
