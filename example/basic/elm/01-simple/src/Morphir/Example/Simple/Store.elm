module Morphir.Example.Simple.Store exposing (..)


type USD = USD
type EUR = EUR
type GBP = GBP
type JPY = JPY

type alias Money c = Money Int

mkDollar : Int -> Money USD
mkDollar amount = Money amount
