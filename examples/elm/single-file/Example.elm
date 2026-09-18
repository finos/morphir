module Example exposing (Amount, Kind(..))


type alias Amount =
    { value : Int }


type Kind
    = Simple
    | Detailed Amount
