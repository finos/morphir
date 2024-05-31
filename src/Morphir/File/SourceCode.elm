{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.File.SourceCode exposing (Doc, concat, dot, dotSep, empty, indent, indentLines, newLine, parens, semi, space)

{-| Utilities related to generating source code.

@docs Doc, concat, dot, dotSep, empty, indent, indentLines, newLine, parens, semi, space

-}


{-| Type that represents a part or the whole document.
-}
type alias Doc =
    String


{-| Empty document.
-}
empty : Doc
empty =
    ""


{-| Single space character.
-}
space : Doc
space =
    " "


{-| Single new line.
-}
newLine : Doc
newLine =
    "\n"


{-| Single semi-colon.
-}
semi : Doc
semi =
    ";"


{-| Single dot character.
-}
dot : Doc
dot =
    "."


{-| Concatenates a list of documents.
-}
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


{-| Concatenates a list of documents separating them with dots.
-}
dotSep : List Doc -> Doc
dotSep parts =
    parts |> String.join dot


{-| Wraps the document into parenthesis.
-}
parens : Doc -> Doc
parens string =
    String.concat [ "(", string, ")" ]
