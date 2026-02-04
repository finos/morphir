module Types exposing (Documentation)

{-| A documentation decoration type.

This decoration can be attached to IR nodes to provide structured documentation
including descriptions, tags, and links.
-}

{-| Documentation decoration with structured metadata.
-}
type alias Documentation =
    { description : String
    , tags : List String
    , links : List Link
    }

{-| A link to external documentation or resources.
-}
type alias Link =
    { label : String
    , url : String
    }
