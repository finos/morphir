module Parity.Modules.Api exposing (Request, isBlank, lookup, start)

{-| The exposed module.

It imports Util with an alias and an exposing list.
-}

import Parity.Modules.Sig as Sig
import Parity.Modules.Tag exposing (Tag(..))
import Parity.Modules.Unused
import Parity.Modules.Util as U exposing (Id, one)


{-| A request. -}
type alias Request =
    { id : Id, count : Int }


start : Request
start =
    { id = U.empty, count = one }


lookup : Id -> Request -> Maybe Int
lookup id request =
    if id == request.id then
        Just request.count

    else
        Nothing


isBlank : Sig.Code -> Bool
isBlank code =
    code == ""


tagged : Tag
tagged =
    Tag 1
