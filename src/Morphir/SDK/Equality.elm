module Morphir.SDK.Equality exposing (equal, notEqual)

{-| Checking if things are the same.

@docs equal, notEqual

-}

import Morphir.SDK.Bool exposing (Bool)


{-| Check if values are &ldquo;the same&rdquo;.
-}
equal : a -> a -> Bool
equal =
    (==)


{-| Check if values are not &ldquo;the same&rdquo;.

So `(notEqual a b)` is the same as `(not (equal a b))`.

-}
notEqual : a -> a -> Bool
notEqual =
    (/=)
