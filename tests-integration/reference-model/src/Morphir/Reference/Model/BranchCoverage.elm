module Morphir.Reference.Model.BranchCoverage exposing (..)


type HTMLStatusCodes
    = InternalServerError
    | BadGateway
    | ServiceUnavailable
    | GatewayTimeout


type alias Code =
    Int


type alias ErrMsg =
    String


simpleIfandElse : Int -> Int -> String
simpleIfandElse a b =
    if a < b then
        "A is greater than B"

    else
        "B is greater than A"


exampleWithLetDefinition : Int -> Int -> Int -> String
exampleWithLetDefinition a b c =
    let
        whichIsGreater =
            if c < a then
                "A is greater"

            else
                "C is greater"
    in
    if  c == a && a == b then
        "All items are equal"

    else
        whichIsGreater


exampleWithPatternMatch : HTMLStatusCodes -> ( Code, ErrMsg )
exampleWithPatternMatch statusCode =
    case statusCode of
        InternalServerError ->
            ( 500, "InternalServerError" )

        BadGateway ->
            ( 502, "BadGateway" )

        ServiceUnavailable ->
            ( 503, "ServiceUnavailable" )

        GatewayTimeout ->
            ( 504, "GatewayTimeout" )


exampleofPatternMatchWithIfandElse : Int -> Int -> HTMLStatusCodes -> String
exampleofPatternMatchWithIfandElse a b statusCode =
    case statusCode of
        InternalServerError ->
            let
                test1 =
                    if a > b then
                        "InternalServerError - A is greater"

                    else
                        "InternalServerError - B is greater"
            in
            test1

        BadGateway ->
            String.append "BadGateway Err - " (is_A_Greater_Than_B a b)

        ServiceUnavailable ->
            "Service Unavailable Err"

        GatewayTimeout ->
            "GatweayTimout Err"


is_A_Greater_Than_B : Int -> Int -> String
is_A_Greater_Than_B a b =
    if a > b then
        "A is greater"

    else
        "B is greater"
