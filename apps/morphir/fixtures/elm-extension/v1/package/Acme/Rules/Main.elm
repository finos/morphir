module Acme.Rules.Main exposing (eligible, priority)


eligible : Bool -> Bool -> Bool
eligible active vip =
    active && not vip


priority : Bool -> Int
priority vip =
    if vip then
        1

    else
        2
