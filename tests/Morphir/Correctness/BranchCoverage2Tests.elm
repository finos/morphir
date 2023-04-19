module Morphir.Correctness.BranchCoverage2Tests exposing (..)

import Expect
import Morphir.Correctness.BranchCoverage as BranchCoverage exposing (Condition(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Test exposing (Test, test)


simpleIfandElseTest : Test
simpleIfandElseTest =
    let
        simpleIfandElseValue : Value () ()
        simpleIfandElseValue =
            Value.IfThenElse ()
                (less (Value.Literal () (WholeNumberLiteral 5)) (Value.Literal () (WholeNumberLiteral 7)))
                (Value.Literal () (StringLiteral "A is greater than B"))
                (Value.Literal () (StringLiteral "B is greater than A"))
    in
    test "Testing simple If and Else Branch"
        (\_ ->
            simpleIfandElseValue
                |> BranchCoverage.valueBranches True
                |> Expect.equal
                    [ [ BoolCondition { criterion = less (intLit 5) (intLit 7), expectedValue = True } ]
                    , [ BoolCondition { criterion = less (intLit 5) (intLit 7), expectedValue = False } ]
                    ]
        )


exampleWithLetDefinition : Test
exampleWithLetDefinition =
    let
        exampleWithLetDefinitionValue : Value () ()
        exampleWithLetDefinitionValue =
            Value.IfThenElse ()
                (apply3 (basics "equals") (intLit 5) (intLit 7) (intLit 3))
                (stringLit "All items are equal")
                (Value.IfThenElse ()
                    (less (intLit 3) (intLit 5))
                    (stringLit "A is greater")
                    (stringLit "C is greater")
                )
    in
    test "Testing simple If and Else by Substitution from a let"
        (\_ ->
            exampleWithLetDefinitionValue
                |> BranchCoverage.valueBranches True
                |> Expect.equal
                    [ [ BoolCondition
                            { criterion =
                                Apply () (Apply () (Apply () (Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "equals" ] )) (Literal () (WholeNumberLiteral 5))) (Literal () (WholeNumberLiteral 7))) (Literal () (WholeNumberLiteral 3))
                            , expectedValue = True
                            }
                      ]
                    , [ BoolCondition
                            { criterion = Apply () (Apply () (Apply () (Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "equals" ] )) (Literal () (WholeNumberLiteral 5))) (Literal () (WholeNumberLiteral 7))) (Literal () (WholeNumberLiteral 3))
                            , expectedValue = False
                            }
                      , BoolCondition
                            { criterion = Apply () (Apply () (Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "less", "than" ] )) (Literal () (WholeNumberLiteral 3))) (Literal () (WholeNumberLiteral 5))
                            , expectedValue = True
                            }
                      ]
                    , [ BoolCondition
                            { criterion = Apply () (Apply () (Apply () (Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "equals" ] )) (Literal () (WholeNumberLiteral 5))) (Literal () (WholeNumberLiteral 7))) (Literal () (WholeNumberLiteral 3))
                            , expectedValue = False
                            }
                      , BoolCondition
                            { criterion = Apply () (Apply () (Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "less", "than" ] )) (Literal () (WholeNumberLiteral 3))) (Literal () (WholeNumberLiteral 5))
                            , expectedValue = False
                            }
                      ]
                    ]
        )


exampleWithPatternMatch : Test
exampleWithPatternMatch =
    let
        value =
            PatternMatch ()
                (Variable () [ "HTMLStatusCodes" ])
                [ ( ConstructorPattern ()
                        (FQName.fromString "" ".")
                        [ LiteralPattern () (StringLiteral "InternalServerError") ]
                  , Value.Tuple () [ intLit 500, stringLit "InternalServerError" ]
                  )
                , ( ConstructorPattern ()
                        (FQName.fromString "" ".")
                        [ LiteralPattern () (StringLiteral "BadGateway") ]
                  , Value.Tuple () [ intLit 502, stringLit "BadGateway" ]
                  )
                , ( ConstructorPattern ()
                        (FQName.fromString "" ".")
                        [ LiteralPattern () (StringLiteral "ServiceUnavailable") ]
                  , Value.Tuple () [ intLit 503, stringLit "ServiceUnavailable" ]
                  )
                , ( ConstructorPattern ()
                        (FQName.fromString "" ".")
                        [ LiteralPattern () (StringLiteral "GatewayTimeout") ]
                  , Value.Tuple () [ intLit 504, stringLit "GatewayTimeout" ]
                  )
                ]
    in
    test "Testing Simple Pattern Match"
        (\_ ->
            value
                |> BranchCoverage.valueBranches True
                |> Expect.equal
                    [ [ PatternCondition
                            { excludes = []
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    , [ PatternCondition
                            { excludes = []
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    , [ PatternCondition
                            { excludes = [ ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ] ]
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "BadGateway") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    , [ PatternCondition
                            { excludes = [ ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ] ]
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "BadGateway") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    , [ PatternCondition
                            { excludes =
                                [ ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ]
                                , ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "BadGateway") ]
                                ]
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "ServiceUnavailable") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    , [ PatternCondition
                            { excludes =
                                [ ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ]
                                , ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "BadGateway") ]
                                ]
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "ServiceUnavailable") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    , [ PatternCondition
                            { excludes =
                                [ ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ]
                                , ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "BadGateway") ]
                                , ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "ServiceUnavailable") ]
                                ]
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "GatewayTimeout") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    , [ PatternCondition
                            { excludes =
                                [ ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "InternalServerError") ]
                                , ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "BadGateway") ]
                                , ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "ServiceUnavailable") ]
                                ]
                            , includes = ConstructorPattern () ( [ [] ], [], [] ) [ LiteralPattern () (StringLiteral "GatewayTimeout") ]
                            , subject = Variable () [ "HTMLStatusCodes" ]
                            }
                      ]
                    ]
        )



-- TODO: Import Utility from branch coverage


apply : Value.Value ta () -> Value.Value ta () -> Value.Value ta ()
apply f a1 =
    Value.Apply () f a1


apply2 : Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta ()
apply2 f a1 a2 =
    Value.Apply () (apply f a1) a2


apply3 : Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta () -> Value.Value ta ()
apply3 f a1 a2 a3 =
    Value.Apply () (apply2 f a1 a2) a3


var : String -> Value () ()
var name =
    Value.Variable () (Name.fromString name)


intLit : Int -> Value ta ()
intLit v =
    Value.Literal () (WholeNumberLiteral v)


stringLit : String -> Value ta ()
stringLit str =
    Value.Literal () (StringLiteral str)


basics : String -> Value () ()
basics localName =
    Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], Name.fromString localName )


eq : String -> Int -> Value.Value () ()
eq varName val =
    apply2 (basics "equal") (var varName) (intLit val)


less : Value.Value () () -> Value.Value () () -> Value.Value () ()
less a b =
    apply2 (basics "lessThan") a b
