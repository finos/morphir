module Morphir.Scala.WellKnownTypes exposing (anyVal)

import Morphir.Scala.AST as A exposing (Type(..))


anyVal : Type
anyVal =
    A.TypeRef [ "scala" ] "AnyVal"


{-| If the given type is a TypeRef, expand it to being the Type Ref of the companion object
which is given by the `.type` accessor in Scala.
-}
toCompanionObjectTypeRef : Type -> Type
toCompanionObjectTypeRef tpe =
    case tpe of
        TypeRef path name ->
            TypeRef (path ++ [ name ]) "type"

        _ ->
            tpe
