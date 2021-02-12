module Morphir.Scala.WellKnownTypes exposing (anyVal)

import Morphir.Scala.AST as A exposing (Type)


anyVal : Type
anyVal =
    A.TypeRef [ "scala" ] "AnyVal"
