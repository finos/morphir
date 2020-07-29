module SlateX.DevBot.Source exposing (..)


{-| Utilities related to generating source code.
-}

empty : String
empty =
    ""


space : String
space =
    " "


newLine : String
newLine =
    "\n"


semi : String
semi =
    ";"


dot : String
dot =
    "."        


{-| Indent the specified string. If the string contains multiple lines they will all be indented.
-}
indent : Int -> String -> String
indent depth string =
    string
        |> String.lines
        |> indentLines depth


{-| Indent the specified list of string. If the string contains multiple lines they will all be indented.
-}
indentLines : Int -> List String -> String
indentLines depth lines =
    lines
        |> List.concatMap String.lines
        |> List.map
            (\line ->
                (String.repeat depth space) ++ line
            )
        |> String.join newLine


dotSep : List String -> String
dotSep parts =
    parts |> String.join dot


parens : String -> String
parens string =
    "(" ++ string ++ ")"    