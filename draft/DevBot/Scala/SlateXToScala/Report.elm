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
