module Morphir.Type.InferTests.BooksAndRecordsTests exposing (..)

import Dict exposing (Dict)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Type.Infer as Infer


packageSpec : Package.Specification ()
packageSpec =
    { modules =
        Dict.fromList
            [ ( Path.fromString "BooksAndRecords"
              , { types =
                    Dict.fromList
                        [ ( Name.fromString "DealCmd"
                          , Documented ""
                                (Type.CustomTypeSpecification []
                                    (Dict.fromList
                                        [ ( Name.fromString "OpenDeal"
                                          , [ ( Name.fromString "productId", stringType () )
                                            , ( Name.fromString "price", floatType () )
                                            , ( Name.fromString "quantity", intType () )
                                            ]
                                          )
                                        ]
                                    )
                                )
                          )
                        , ( Name.fromString "DealEvent"
                          , Documented ""
                                (Type.CustomTypeSpecification []
                                    (Dict.fromList
                                        [ ( Name.fromString "DealOpened"
                                          , [ ( Name.fromString "productId", stringType () )
                                            , ( Name.fromString "price", floatType () )
                                            , ( Name.fromString "quantity", intType () )
                                            ]
                                          )
                                        , ( Name.fromString "InvalidPrice"
                                          , [ ( Name.fromString "price", floatType () )
                                            ]
                                          )
                                        ]
                                    )
                                )
                          )
                        ]
                , values =
                    Dict.empty
                , doc = Nothing
                }
              )
            ]
    }


tFun arg ret =
    Type.Function () arg ret


varPattern name tpe =
    Value.AsPattern tpe (Value.WildcardPattern tpe) (Name.fromString name)


testReferences : Dict PackageName (Package.Specification ())
testReferences =
    Dict.fromList
        [ ( Path.fromString "BooksAndRecords"
          , packageSpec
          )
        ]


positiveOutcomes : List (Value () (Type ()))
positiveOutcomes =
    let
        dealEventType =
            Type.Reference () (fqn "BooksAndRecords" "BooksAndRecords" "DealEvent") []

        dealOpened0 =
            Value.Constructor (tFun (stringType ()) (tFun (floatType ()) (tFun (intType ()) dealEventType)))
                (fqn "BooksAndRecords" "BooksAndRecords" "DealOpened")

        dealOpened1 =
            Value.Apply (tFun (floatType ()) (tFun (intType ()) dealEventType))
                dealOpened0
                (Value.Literal (stringType ()) (StringLiteral "foo"))

        dealOpened2 =
            Value.Apply (tFun (intType ()) dealEventType)
                dealOpened1
                (Value.Literal (floatType ()) (FloatLiteral 3.14))

        dealOpened3 =
            Value.Apply dealEventType
                dealOpened2
                (Value.Literal (intType ()) (WholeNumberLiteral 1500))

        dealCommandType =
            Type.Reference () (fqn "BooksAndRecords" "BooksAndRecords" "DealCmd") []

        openDealPattern =
            Value.ConstructorPattern dealCommandType
                (fqn "BooksAndRecords" "BooksAndRecords" "OpenDeal")
                [ varPattern "productId" (stringType ())
                , varPattern "price" (floatType ())
                , varPattern "quantity" (intType ())
                ]

        dealCommandPatternMatch subject =
            Value.PatternMatch dealEventType
                subject
                [ ( openDealPattern, dealOpened3 )
                ]

        logicLambda =
            Value.Lambda (tFun dealCommandType dealEventType)
                (varPattern "dealCmd" dealCommandType)
                (dealCommandPatternMatch (Value.Variable dealCommandType (Name.fromString "dealCmd")))

        priceCheck =
            Value.IfThenElse dealEventType
                (Value.Apply (boolType ())
                    (Value.Apply (tFun (floatType ()) (boolType ()))
                        (Value.Reference (tFun (floatType ()) (tFun (floatType ()) (boolType ())))
                            (fqn "Morphir.SDK" "Basics" "lessThan")
                        )
                        (Value.Literal (floatType ()) (FloatLiteral 1))
                    )
                    (Value.Literal (floatType ()) (FloatLiteral 0))
                )
                (Value.Apply dealEventType
                    (Value.Constructor (tFun (floatType ()) dealEventType)
                        (fqn "BooksAndRecords" "BooksAndRecords" "InvalidPrice")
                    )
                    (Value.Literal (floatType ()) (FloatLiteral 1))
                )
                dealOpened3
    in
    [ dealOpened0
    , dealOpened1
    , dealOpened2
    , dealOpened3
    , logicLambda
    , priceCheck
    ]
