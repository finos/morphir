module Morphir.Spark.API exposing (..)

import Morphir.Scala.AST as Scala


dataFrame : Scala.Type
dataFrame =
    Scala.TypeRef [ "org", "apache", "spark", "sql" ] "DataFrame"


literal : Scala.Value -> Scala.Value
literal lit =
    Scala.Apply (Scala.Ref [ "org", "apache", "spark", "sql", "functions" ] "lit")
        [ Scala.ArgValue Nothing lit ]


column : String -> Scala.Value
column name =
    Scala.Apply (Scala.Ref [ "org", "apache", "spark", "sql", "functions" ] "col")
        [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit name)) ]


when : Scala.Value -> Scala.Value -> Scala.Value
when cond thenBranch =
    Scala.Apply (Scala.Ref [ "org", "apache", "spark", "sql", "functions" ] "when")
        [ Scala.ArgValue Nothing cond, Scala.ArgValue Nothing thenBranch ]


andWhen : Scala.Value -> Scala.Value -> Scala.Value -> Scala.Value
andWhen cond thenBranch soFar =
    Scala.Apply
        (Scala.Select soFar "when")
        [ Scala.ArgValue Nothing cond, Scala.ArgValue Nothing thenBranch ]


otherwise : Scala.Value -> Scala.Value -> Scala.Value
otherwise elseBranch soFar =
    Scala.Apply
        (Scala.Select soFar "otherwise")
        [ Scala.ArgValue Nothing elseBranch ]


alias : String -> Scala.Value -> Scala.Value
alias name value =
    Scala.Apply
        (Scala.Select value "alias")
        [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit name)) ]


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


aggregate : String -> List Scala.Value -> Scala.Value -> Scala.Value
aggregate groupField aggregations from =
    Scala.Apply
        (Scala.Select
            (Scala.Apply
                (Scala.Select from "groupBy")
                [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit groupField)) ]
            )
            "agg"
        )
        (aggregations
            |> List.map (Scala.ArgValue Nothing)
        )
