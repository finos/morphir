module Morphir.Snowpark.Operatorsmaps exposing (mapOperator)

mapOperator : List String -> String
mapOperator name =
    case name of
        ["add"] ->
            "+"
        ["subtract"] ->
            "-"
        ["multiply"] ->
            "*"
        ["divide"] ->
            "/"
        ["integer", "divide"] ->
            "/"
        ["float", "divide"] ->
            "/"
        _ ->
            "Unsupported"