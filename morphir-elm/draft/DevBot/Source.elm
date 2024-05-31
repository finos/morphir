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