module Morphir.Relational.Spark.Backend exposing (..)

import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Relational.IR exposing (JoinType(..), OuterJoinType(..), Relation(..))
import Morphir.Scala.AST as Scala


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


mapRelation : Relation -> Scala.Value
mapRelation relation =
    case relation of
        From name ->
            Scala.Variable (Name.toCamelCase name)

        Where predicate sourceRelation ->
            Scala.Apply
                (Scala.Select
                    (mapRelation sourceRelation)
                    "where"
                )
                [ Scala.ArgValue Nothing (mapColumnExpression predicate)
                ]

        Select columns sourceRelation ->
            Scala.Apply
                (Scala.Select
                    (mapRelation sourceRelation)
                    "select"
                )
                (columns
                    |> List.map (mapColumnExpression >> Scala.ArgValue Nothing)
                )

        Join joinType predicate leftRelation rightRelation ->
            let
                joinTypeLabel : String
                joinTypeLabel =
                    case joinType of
                        Inner ->
                            "inner"

                        Outer Left ->
                            "left"

                        Outer Right ->
                            "right"

                        Outer Full ->
                            "full"
            in
            Scala.Apply
                (Scala.Select
                    (mapRelation leftRelation)
                    "join"
                )
                [ Scala.ArgValue Nothing (mapRelation rightRelation)
                , Scala.ArgValue Nothing (mapColumnExpression predicate)
                , Scala.ArgValue Nothing
                    (Scala.Literal
                        (Scala.StringLit joinTypeLabel)
                    )
                ]


mapColumnExpression : Value ta va -> Scala.Value
mapColumnExpression value =
    let
        default v =
            ScalaBackend.
    in
    case value of
        Value.Apply _ (Value.Apply _ (Value.Reference _ fqn) arg1) arg2 ->
            case FQName.toString fqn of
                "Morphir.SDK:Basics:equal" ->
                    Scala.BinOp (mapColumnExpression arg1) "===" (mapColumnExpression arg2)

                _ ->
                    default