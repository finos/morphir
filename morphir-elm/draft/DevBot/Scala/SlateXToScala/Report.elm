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


module SlateX.DevBot.Scala.SlateXToScala.Report exposing (..)


import SlateX.DevBot.Scala.AST as S


todoValue : String -> S.Value
todoValue message =
    S.CommentedValue
        (S.Ref [ "scala", "Predef" ] "???")
        message


todoPattern : String -> S.Pattern
todoPattern message =
    S.CommentedPattern
        S.WildcardMatch
        message


todoType : String -> S.Type
todoType message =
    S.CommentedType
        (S.TypeRef [ "scala" ] "Nothing")
        message   
