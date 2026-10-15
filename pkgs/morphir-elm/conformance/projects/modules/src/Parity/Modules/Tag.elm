module Parity.Modules.Tag exposing (Tag(..))

{-| Api uses `Tag` in a value signature and as a constructor in a body. Neither keeps the module.
-}


type Tag
    = Tag Int
