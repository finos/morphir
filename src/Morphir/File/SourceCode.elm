module Morphir.File.SourceCode exposing (..)


type alias Doc =
    String


{-| Utilities related to generating source code.
-}
empty : Doc
empty =
    ""


space : Doc
space =
    " "


newLine : Doc
newLine =
    "\n"


semi : Doc
semi =
    ";"


dot : Doc
dot =
    "."


concat : List Doc -> Doc
concat =
    String.concat


{-| Indent the specified string. If the string contains multiple lines they will all be indented.
-}
indent : Int -> Doc -> Doc
indent depth string =
    string
        |> String.lines
        |> indentLines depth


{-| Indent the specified list of string. If the string contains multiple lines they will all be indented.
-}
indentLines : Int -> List Doc -> Doc
indentLines depth lines =
    lines
        |> List.concatMap String.lines
        |> List.map
            (\line ->
                String.append (String.repeat depth space) line
            )
        |> String.join newLine


dotSep : List Doc -> Doc
dotSep parts =
    parts |> String.join dot


parens : Doc -> Doc
parens string =
    String.concat [ "(", string, ")" ]
