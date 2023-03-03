module Morphir.Scala.Common exposing (..)

import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.Scala.AST as Scala
import Set exposing (Set)


{-| Map IR value to Scala Value
-}
mapValueName : Name -> String
mapValueName name =
    let
        scalaName : String
        scalaName =
            Name.toCamelCase name
    in
    if Set.member scalaName scalaKeywords || Set.member scalaName javaObjectMethods then
        "_" ++ scalaName

    else
        scalaName


prefixKeywords : List String -> List String
prefixKeywords strings =
    strings |> List.map prefixKeyword


prefixKeyword : String -> String
prefixKeyword word =
    if Set.member word scalaKeywords then
        "_" ++ word

    else
        word


mapPathToScalaPath : Path -> Scala.Path
mapPathToScalaPath path =
    path
        |> List.map
            (\name ->
                name |> mapValueName
            )


{-| Scala keywords that cannot be used as variable name.
-}
scalaKeywords : Set String
scalaKeywords =
    Set.fromList
        [ "abstract"
        , "case"
        , "catch"
        , "class"
        , "def"
        , "do"
        , "else"
        , "extends"
        , "false"
        , "final"
        , "finally"
        , "for"
        , "forSome"
        , "if"
        , "implicit"
        , "import"
        , "lazy"
        , "macro"
        , "match"
        , "new"
        , "null"
        , "object"
        , "override"
        , "package"
        , "private"
        , "protected"
        , "return"
        , "sealed"
        , "super"
        , "this"
        , "throw"
        , "trait"
        , "try"
        , "true"
        , "type"
        , "val"
        , "var"
        , "while"
        , "with"
        , "yield"
        ]


{-| We cannot use any method names in `java.lang.Object` because values are represented as functions/values in a Scala
object which implicitly inherits those methods which can result in name collisions.
-}
javaObjectMethods : Set String
javaObjectMethods =
    Set.fromList
        [ "clone"
        , "equals"
        , "finalize"
        , "getClass"
        , "hashCode"
        , "notify"
        , "notifyAll"
        , "toString"
        , "wait"
        ]
