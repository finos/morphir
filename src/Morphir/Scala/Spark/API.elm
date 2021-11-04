module Morphir.Scala.Spark.API exposing (..)

import Morphir.Scala.AST as Scala


dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"


select : List Scala.Value -> Scala.Value -> Scala.Value
select columns from =
    Scala.Apply
        (Scala.Select
            from
            "select"
        )
        (columns
            |> List.map (Scala.ArgValue Nothing)
        )


filter : Scala.Value -> Scala.Value -> Scala.Value
filter predicate from =
    Scala.Apply
        (Scala.Select
            from
            "filter"
        )
        [ Scala.ArgValue Nothing predicate
        ]


join : Scala.Value -> Scala.Value -> String -> Scala.Value -> Scala.Value
join rightRelation predicate joinTypeLabel leftRelation =
    Scala.Apply
        (Scala.Select
            leftRelation
            "join"
        )
        [ Scala.ArgValue Nothing rightRelation
        , Scala.ArgValue Nothing predicate
        , Scala.ArgValue Nothing
            (Scala.Literal
                (Scala.StringLit joinTypeLabel)
            )
        ]
