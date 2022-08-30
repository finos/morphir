module SparkTests.DataDefinition.Field.Category exposing (..)


type Category
    = PaintCollections
    | HouseHoldCollection
    | SimpleToolCollection
    | Diary


categoryFromString : String -> Result String Category
categoryFromString str =
    if String.isEmpty str then
        Err "Empty strings are not valid Antique Category strings."

    else
        case str of
            "PaintCollections" ->
                PaintCollections |> Ok

            "HouseHoldCollection" ->
                HouseHoldCollection |> Ok

            "SimpleToolCollection" ->
                SimpleToolCollection |> Ok

            "Diary" ->
                Diary |> Ok

            _ ->
                Err "Invalid Antique Category string."


categoryToString : Maybe Category -> String
categoryToString category =
    category
        |> Maybe.map
            (\cat ->
                case cat of
                    PaintCollections ->
                        "PaintCollections"

                    HouseHoldCollection ->
                        "HouseHoldCollection"

                    SimpleToolCollection ->
                        "SimpleToolCollection"

                    Diary ->
                        "Diary"
            )
        |> Maybe.withDefault ""
