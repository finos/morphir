module Morphir.Reference.Model.TupleSDK exposing (..)


tuplePair : a -> b -> ( a, b )
tuplePair a b =
    Tuple.pair a b


tupleFirst : ( a, b ) -> a
tupleFirst value =
    Tuple.first value


tupleSecond : ( a, b ) -> b
tupleSecond value =
    Tuple.second value


tupleMapFirst : String -> b -> ( String, b )
tupleMapFirst string int =
    Tuple.mapFirst String.reverse ( string, int )


tupleMapSecond : a -> Float -> ( a, Float )
tupleMapSecond string int =
    Tuple.mapSecond sqrt ( string, int )


tupleMapBoth : String -> Float -> ( String, Float )
tupleMapBoth string int =
    Tuple.mapBoth String.reverse sqrt ( string, int )
