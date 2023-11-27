module Morphir.Snowpark.PatternMatchTests exposing (caseOfGenTests)

import Expect
import Test exposing (Test, describe, test)
import Dict exposing (Dict(..))
import Set 
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value
import Morphir.IR.Type as Type
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Morphir.IR.Value as Value
import Morphir.Snowpark.CommonTestUtils exposing (stringTypeInstance
                                                 , testDistributionName
                                                 , testDistributionPackage)
import Morphir.IR.Literal as Literal
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)

str : Type.Type ()
str = stringTypeInstance

aLit : Literal.Literal
aLit = (Literal.stringLiteral "A")

a2Lit : Literal.Literal
a2Lit = (Literal.stringLiteral "a")

caseOfGenTests: Test
caseOfGenTests =
    let
        customizationOptions = {functionsToInline = Set.empty, functionsToCache = Set.empty}
        (calculatedContext, _ , _) = MappingContext.processDistributionModules testDistributionName testDistributionPackage customizationOptions
        cases = [ (Value.LiteralPattern str aLit, Value.Literal str a2Lit)
                , (Value.WildcardPattern str, Value.Literal str (Literal.stringLiteral "D"))]
        inputCase = Value.PatternMatch stringTypeInstance (Value.Literal str (Literal.stringLiteral "X")) cases

        (mappedCase, _) = mapValue inputCase { emptyValueMappingContext | typesContextInfo = calculatedContext }

        mappedCaseParts = 
              case mappedCase of
                Scala.Apply
                    (Scala.Select
                        (Scala.Apply
                            (Scala.Ref _  "when")
                            [ Scala.ArgValue _ (Scala.BinOp left1 "===" right1), Scala.ArgValue _ result1 ])
                        "otherwise")
                    [ Scala.ArgValue _ result2 ] ->
                        [left1, right1, result1, result2]
                _ -> 
                    []
        
        assertCaseWithLiterals =
            test ("Convert case of with literals") <|
            \_ ->
                Expect.equal [ applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "X")]
                             , applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "A")]
                             , applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "a")]
                             , applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "D")]] 
                             mappedCaseParts

    in
    describe "PatternConversionTests"
        [
            assertCaseWithLiterals
        ]