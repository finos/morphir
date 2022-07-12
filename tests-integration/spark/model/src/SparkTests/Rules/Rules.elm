module SparkTests.Rules.Rules exposing (..)


applyRules : Bool -> String -> Float -> List ( String, Float )
applyRules condition name amount =
    if condition then
        [ ( name, amount ) ]

    else
        []


type Rule
    = Rule_1
    | Rule_2
    | Rule_3
    | Rule_4
    | Rule_5
    | Rule_7
    | Rule_8
    | Rule_9


rule : List Rule
rule =
    List.concat
        [ bankruptcyDeclaration
        , financialFreedomDeclaration
        , totalAssetsSeizure
        ]


bankruptcyDeclaration : List Rule
bankruptcyDeclaration =
    [ Rule_1
    , Rule_2
    , Rule_5
    ]


financialFreedomDeclaration : List Rule
financialFreedomDeclaration =
    [ Rule_2
    , Rule_4
    , Rule_9
    ]


totalAssetsSeizure : List Rule
totalAssetsSeizure =
    [ Rule_7
    , Rule_8
    , Rule_3
    ]
