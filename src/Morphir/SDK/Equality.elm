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
