module Morphir.Reference.Model.Issues.PatternModel.BasicRule exposing (..)

import Morphir.Reference.Model.Issues.PatternModel.BasicEnum exposing (..)
import Morphir.Reference.Model.Issues.PatternModel.OtherBasicEnum exposing (OtherBasicEnum(..))
import Morphir.SDK.Rule as Rule exposing (Rule, any, anyOf, is)


type alias BasicRule =
    { basic_enum : BasicEnum
    , other_basic_enum : OtherBasicEnum
    , id : String
    }


basicRuleSet : Rule BasicRule String



--                      basic_enum          other_basic_enum    id      result


basicRuleSet =
    Rule.chain
        [ rule (is One) (is A) any "foo"
        , rule (is One) (anyOf [ B, C, D ]) any "bar"
        , rule (is One) any any "foobar"
        , rule (anyOf [ Two, Three, Four ]) any any "baz"
        , rule any any any "foobarbaz"
        ]


rule : (BasicEnum -> Bool) -> (OtherBasicEnum -> Bool) -> (String -> Bool) -> String -> BasicRule -> Maybe String
rule matchBasicEnum matchOtherBasicEnum matchId result data =
    if
        matchBasicEnum data.basic_enum
            && matchOtherBasicEnum data.other_basic_enum
            && matchId data.id
    then
        Just result

    else
        Nothing
