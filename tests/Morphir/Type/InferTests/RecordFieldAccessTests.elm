module Morphir.Type.InferTests.RecordFieldAccessTests exposing (..)

import Dict exposing (Dict)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


recordWithVarType : Type ()
recordWithVarType =
    Type.Record ()
        [ Type.Field (Name.fromString "field1")
            (Type.Reference ()
                (fqn "Morphir.SDK" "Maybe" "Maybe")
                [ Type.Variable () (Name.fromString "a") ]
            )
        , Type.Field (Name.fromString "field2")
            (Type.Reference ()
                (fqn "Morphir.SDK" "Maybe" "Maybe")
                [ Type.Reference () (fqn "Morphir.SDK" "String" "String") [] ]
            )
        ]


recordType : Type ()
recordType =
    Type.Record ()
        [ Type.Field (Name.fromString "field1")
            (Type.Reference ()
                (fqn "Morphir.SDK" "Maybe" "Maybe")
                [ Type.Reference () (fqn "Morphir.SDK" "String" "String") [] ]
            )
        , Type.Field (Name.fromString "field2")
            (Type.Reference ()
                (fqn "Morphir.SDK" "Maybe" "Maybe")
                [ Type.Reference () (fqn "Morphir.SDK" "String" "String") [] ]
            )
        ]


packageSpec : Package.Specification ()
packageSpec =
    { modules =
        Dict.fromList
            [ ( Path.fromString "RecordAccess"
              , { types =
                    Dict.fromList
                        [ ( Name.fromString "Rec"
                          , Documented ""
                                (Type.TypeAliasSpecification []
                                    recordType
                                )
                          )
                        , ( Name.fromString "RecWithVar"
                          , Documented ""
                                (Type.TypeAliasSpecification [ Name.fromString "a" ]
                                    recordWithVarType
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


positiveDefOutcomes : List (Value.Definition () ( Int, Type () ))
positiveDefOutcomes =
    let
        variableRecType : Type ()
        variableRecType =
            Type.Reference ()
                (fqn "RecordAccess" "RecordAccess" "RecWithVar")
                [ Type.Variable () (Name.fromString "a") ]

        maybeStringType : Type ()
        maybeStringType =
            Type.Reference ()
                (fqn "Morphir.SDK" "Maybe" "Maybe")
                [ Type.Reference () (fqn "Morphir.SDK" "String" "String") [] ]

        maybeVariableType : Type ()
        maybeVariableType =
            Type.Reference ()
                (fqn "Morphir.SDK" "Maybe" "Maybe")
                [ Type.Variable () (Name.fromString "a") ]

        predicateWithTypeParamValue : Value () ( Int, Type () )
        predicateWithTypeParamValue =
            Value.Apply ( 46, boolType () )
                (Value.Apply ( 18, tFun (boolType ()) (boolType ()) )
                    (Value.Reference ( 5, tFun (boolType ()) (tFun (boolType ()) (boolType ())) )
                        (fqn "Morphir.SDK" "Basics" "and")
                    )
                    (Value.Apply ( 17, boolType () )
                        (Value.Apply ( 13, tFun maybeVariableType (boolType ()) )
                            (Value.Reference ( 9, tFun maybeVariableType (tFun maybeVariableType (boolType ())) )
                                (fqn "Morphir.SDK" "Basics" "equal")
                            )
                            (Value.Field ( 10, maybeVariableType )
                                (Value.Variable ( 1, variableRecType ) (Name.fromString "rec"))
                                (Name.fromString "field1")
                            )
                        )
                        (Value.Constructor ( 16, maybeVariableType )
                            (fqn "Morphir.SDK" "Maybe" "Nothing")
                        )
                    )
                )
                (Value.Apply ( 45, boolType () )
                    (Value.Apply ( 32, tFun (boolType ()) (boolType ()) )
                        (Value.Reference ( 19, tFun (boolType ()) (tFun (boolType ()) (boolType ())) )
                            (fqn "Morphir.SDK" "Basics" "and")
                        )
                        (Value.Apply ( 31, boolType () )
                            (Value.Apply ( 27, tFun maybeStringType (boolType ()) )
                                (Value.Reference ( 23, tFun maybeStringType (tFun maybeStringType (boolType ())) )
                                    (fqn "Morphir.SDK" "Basics" "equal")
                                )
                                (Value.Field ( 24, maybeStringType )
                                    (Value.Variable ( 1, variableRecType ) (Name.fromString "rec"))
                                    (Name.fromString "field2")
                                )
                            )
                            (Value.Constructor ( 30, maybeStringType )
                                (fqn "Morphir.SDK" "Maybe" "Nothing")
                            )
                        )
                    )
                    (Value.Apply ( 44, boolType () )
                        (Value.Apply ( 40, tFun maybeVariableType (boolType ()) )
                            (Value.Reference ( 36, tFun maybeVariableType (tFun maybeVariableType (boolType ())) )
                                (fqn "Morphir.SDK" "Basics" "equal")
                            )
                            (Value.Field ( 37, maybeVariableType )
                                (Value.Variable ( 1, variableRecType ) (Name.fromString "rec"))
                                (Name.fromString "field1")
                            )
                        )
                        (Value.Constructor ( 43, maybeVariableType )
                            (fqn "Morphir.SDK" "Maybe" "Nothing")
                        )
                    )
                )

        predicateWithTypeParamDefinition : Value.Definition () ( Int, Type () )
        predicateWithTypeParamDefinition =
            { inputTypes = [ ( Name.fromString "rec", ( 0, variableRecType ), variableRecType ) ]
            , outputType = boolType ()
            , body = predicateWithTypeParamValue
            }
    in
    [ predicateWithTypeParamDefinition
    ]
