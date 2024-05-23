module Morphir.Reference.Model.BooksAndRecordsTests exposing (..)

import Expect
import Morphir.Reference.Model.BooksAndRecords as BooksAndRecords exposing (..)
import Morphir.SDK.StatefulApp exposing (StatefulApp)
import Test exposing (Test, test)


scenarios : Test
scenarios =
    let
        id =
            ""

        qty =
            100

        price =
            123
    in
    BooksAndRecords.app
        |> scenario "Open and close"
            { givenState = Nothing
            , whenCommandsReceived =
                [ OpenDeal id price qty
                , CloseDeal id
                ]
            , thenExpect =
                { state = Nothing
                , events =
                    [ DealOpened id price qty
                    , DealClosed id
                    ]
                }
            }


type alias TestScenario c s e =
    { givenState : Maybe s
    , whenCommandsReceived : List c
    , thenExpect :
        { state : Maybe s
        , events : List e
        }
    }


scenario : String -> TestScenario c s e -> StatefulApp k c s e -> Test
scenario name s (StatefulApp businessLogic) =
    test name
        (\_ ->
            s.whenCommandsReceived
                |> List.foldl
                    (\nextCommand ( state, events ) ->
                        let
                            ( nextState, newEvent ) =
                                businessLogic state nextCommand
                        in
                        ( nextState, List.append events [ newEvent ] )
                    )
                    ( s.givenState, [] )
                |> Expect.equal
                    ( s.thenExpect.state, s.thenExpect.events )
        )
