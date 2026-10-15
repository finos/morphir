module SparkTests.DataDefinition.Field.Report exposing (..)


type FeedBack
    = Genuine
    | Fake


feedBackFromString : String -> Result String FeedBack
feedBackFromString str =
    if String.isEmpty str then
        Err "Empty strings are not valid FeedBack strings."

    else
        case str of
            "Genuine" ->
                Genuine |> Ok

            "Fake" ->
                Fake |> Ok

            _ ->
                Err "Invalid FeedBack string."


feedBackToString : Maybe FeedBack -> String
feedBackToString feedBack =
    feedBack
        |> Maybe.map
            (\fb ->
                case fb of
                    Genuine ->
                        "Genuine"

                    Fake ->
                        "Fake"
            )
        |> Maybe.withDefault ""
