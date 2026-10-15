module Morphir.Reference.Model.SDK.UUID exposing (..)

import Morphir.SDK.UUID as UUID exposing (Error, UUID)


parseUUID : String -> Result Error UUID
parseUUID input =
    UUID.parse input


fromString : String -> Maybe UUID
fromString input =
    UUID.fromString input
