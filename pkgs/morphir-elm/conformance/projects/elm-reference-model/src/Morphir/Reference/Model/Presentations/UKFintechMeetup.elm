module Morphir.Reference.Model.Presentations.UKFintechMeetup exposing (..)


request : Bool -> Int -> Int -> Response
request allowPartial availableSurfboards requestedSurfboards =
    if availableSurfboards < requestedSurfboards then
        if allowPartial then
            Reserved (min availableSurfboards requestedSurfboards)

        else
            Rejected

    else
        Reserved requestedSurfboards


type Response
    = Rejected
    | Reserved Int
