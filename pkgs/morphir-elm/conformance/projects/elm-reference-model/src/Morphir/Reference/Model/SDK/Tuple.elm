module Morphir.Reference.Model.SDK.Tuple exposing (..)


tuplePair : a -> b -> ( a, b )
tuplePair a b =
    Tuple.pair a b


tupleFirst : ( a, b ) -> a
tupleFirst value =
    Tuple.first value


tupleSecond : ( a, b ) -> b
tupleSecond value =
    Tuple.second value


tupleMapFirst : ( String, Float ) -> ( String, Float )
tupleMapFirst tuple =
    Tuple.mapFirst String.reverse tuple


tupleMapSecond : ( String, Float ) -> ( String, Float )
tupleMapSecond tuple =
    Tuple.mapSecond sqrt tuple


tupleMapBoth : ( String, Float ) -> ( String, Float )
tupleMapBoth tuple =
    Tuple.mapBoth String.reverse sqrt tuple
