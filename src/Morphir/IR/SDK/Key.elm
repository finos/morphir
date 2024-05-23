{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.IR.SDK.Key exposing (..)

import Dict exposing (Dict)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (intType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModuleName
moduleName =
    Path.fromString "Key"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Key0", TypeAliasSpecification [] (intType ()) |> Documented "" )
            , ( Name.fromString "Key2", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key3", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key4", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key5", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key6", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key7", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key8", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key9", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key10", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key11", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key12", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key13", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key14", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key15", OpaqueTypeSpecification [] |> Documented "" )
            , ( Name.fromString "Key16", OpaqueTypeSpecification [] |> Documented "" )
            ]
    , values =
        Dict.fromList
            [ vSpec "noKey" [ ( "a", tVar "a" ) ] (key0Type ())
            , vSpec "key0"
                [ ( "a", tVar "a" ) ]
                (key0Type ())
            , vSpec "key2"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "a", tVar "a" )
                ]
                (key2Type ()
                    (tVar "b1")
                    (tVar "b2")
                )
            , vSpec "key3"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "a", tVar "a" )
                ]
                (key3Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                )
            , vSpec "key4"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "a", tVar "a" )
                ]
                (key4Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                )
            , vSpec "key5"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "a", tVar "a" )
                ]
                (key5Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                )
            , vSpec "key6"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "a", tVar "a" )
                ]
                (key6Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                )
            , vSpec "key7"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "a", tVar "a" )
                ]
                (key7Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                )
            , vSpec "key8"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "a", tVar "a" )
                ]
                (key8Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                )
            , vSpec "key9"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "a", tVar "a" )
                ]
                (key9Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                )
            , vSpec "key10"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "getKey10", tFun [ tVar "a" ] (tVar "b10") )
                , ( "a", tVar "a" )
                ]
                (key10Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                    (tVar "b10")
                )
            , vSpec "key11"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "getKey10", tFun [ tVar "a" ] (tVar "b10") )
                , ( "getKey11", tFun [ tVar "a" ] (tVar "b11") )
                , ( "a", tVar "a" )
                ]
                (key11Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                    (tVar "b10")
                    (tVar "b11")
                )
            , vSpec "key12"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "getKey10", tFun [ tVar "a" ] (tVar "b10") )
                , ( "getKey11", tFun [ tVar "a" ] (tVar "b11") )
                , ( "getKey12", tFun [ tVar "a" ] (tVar "b12") )
                , ( "a", tVar "a" )
                ]
                (key12Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                    (tVar "b10")
                    (tVar "b11")
                    (tVar "b12")
                )
            , vSpec "key13"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "getKey10", tFun [ tVar "a" ] (tVar "b10") )
                , ( "getKey11", tFun [ tVar "a" ] (tVar "b11") )
                , ( "getKey12", tFun [ tVar "a" ] (tVar "b12") )
                , ( "getKey13", tFun [ tVar "a" ] (tVar "b13") )
                , ( "a", tVar "a" )
                ]
                (key13Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                    (tVar "b10")
                    (tVar "b11")
                    (tVar "b12")
                    (tVar "b13")
                )
            , vSpec "key14"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "getKey10", tFun [ tVar "a" ] (tVar "b10") )
                , ( "getKey11", tFun [ tVar "a" ] (tVar "b11") )
                , ( "getKey12", tFun [ tVar "a" ] (tVar "b12") )
                , ( "getKey13", tFun [ tVar "a" ] (tVar "b13") )
                , ( "getKey14", tFun [ tVar "a" ] (tVar "b14") )
                , ( "a", tVar "a" )
                ]
                (key14Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                    (tVar "b10")
                    (tVar "b11")
                    (tVar "b12")
                    (tVar "b13")
                    (tVar "b14")
                )
            , vSpec "key15"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "getKey10", tFun [ tVar "a" ] (tVar "b10") )
                , ( "getKey11", tFun [ tVar "a" ] (tVar "b11") )
                , ( "getKey12", tFun [ tVar "a" ] (tVar "b12") )
                , ( "getKey13", tFun [ tVar "a" ] (tVar "b13") )
                , ( "getKey14", tFun [ tVar "a" ] (tVar "b14") )
                , ( "getKey15", tFun [ tVar "a" ] (tVar "b15") )
                , ( "a", tVar "a" )
                ]
                (key15Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                    (tVar "b10")
                    (tVar "b11")
                    (tVar "b12")
                    (tVar "b13")
                    (tVar "b14")
                    (tVar "b15")
                )
            , vSpec "key16"
                [ ( "getKey1", tFun [ tVar "a" ] (tVar "b1") )
                , ( "getKey2", tFun [ tVar "a" ] (tVar "b2") )
                , ( "getKey3", tFun [ tVar "a" ] (tVar "b3") )
                , ( "getKey4", tFun [ tVar "a" ] (tVar "b4") )
                , ( "getKey5", tFun [ tVar "a" ] (tVar "b5") )
                , ( "getKey6", tFun [ tVar "a" ] (tVar "b6") )
                , ( "getKey7", tFun [ tVar "a" ] (tVar "b7") )
                , ( "getKey8", tFun [ tVar "a" ] (tVar "b8") )
                , ( "getKey9", tFun [ tVar "a" ] (tVar "b9") )
                , ( "getKey10", tFun [ tVar "a" ] (tVar "b10") )
                , ( "getKey11", tFun [ tVar "a" ] (tVar "b11") )
                , ( "getKey12", tFun [ tVar "a" ] (tVar "b12") )
                , ( "getKey13", tFun [ tVar "a" ] (tVar "b13") )
                , ( "getKey14", tFun [ tVar "a" ] (tVar "b14") )
                , ( "getKey15", tFun [ tVar "a" ] (tVar "b15") )
                , ( "getKey16", tFun [ tVar "a" ] (tVar "b16") )
                , ( "a", tVar "a" )
                ]
                (key16Type ()
                    (tVar "b1")
                    (tVar "b2")
                    (tVar "b3")
                    (tVar "b4")
                    (tVar "b5")
                    (tVar "b6")
                    (tVar "b7")
                    (tVar "b8")
                    (tVar "b9")
                    (tVar "b10")
                    (tVar "b11")
                    (tVar "b12")
                    (tVar "b13")
                    (tVar "b14")
                    (tVar "b15")
                    (tVar "b16")
                )
            ]
    , doc = Nothing
    }


{-| Create a type key with 0 types.
-}
key0Type : a -> Type a
key0Type attributes =
    Reference attributes (toFQName moduleName "Key0") []


{-| Create a type key with 2 types.
-}
key2Type : a -> Type a -> Type a -> Type a
key2Type attributes itemType1 itemType2 =
    Reference attributes (toFQName moduleName "Key2") [ itemType1, itemType2 ]


{-| Create a type key with 3 types.
-}
key3Type : a -> Type a -> Type a -> Type a -> Type a
key3Type attributes itemType1 itemType2 itemType3 =
    Reference attributes (toFQName moduleName "Key3") [ itemType1, itemType2, itemType3 ]


{-| Create a type key with 4 types.
-}
key4Type : a -> Type a -> Type a -> Type a -> Type a -> Type a
key4Type attributes itemType1 itemType2 itemType3 itemType4 =
    Reference attributes (toFQName moduleName "Key4") [ itemType1, itemType2, itemType3, itemType4 ]


{-| Create a type key with 5 types.
-}
key5Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key5Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 =
    Reference attributes (toFQName moduleName "Key5") [ itemType1, itemType2, itemType3, itemType4, itemType5 ]


{-| Create a type key with 6 types.
-}
key6Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key6Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 =
    Reference attributes (toFQName moduleName "Key6") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6 ]


{-| Create a type key with 7 types.
-}
key7Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key7Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 =
    Reference attributes (toFQName moduleName "Key7") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7 ]


{-| Create a type key with 8 types.
-}
key8Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key8Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 =
    Reference attributes (toFQName moduleName "Key8") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8 ]


{-| Create a type key with 9 types.
-}
key9Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key9Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 =
    Reference attributes (toFQName moduleName "Key9") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9 ]


{-| Create a type key with 10 types.
-}
key10Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key10Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 itemType10 =
    Reference attributes (toFQName moduleName "Key10") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9, itemType10 ]


{-| Create a type key with 11 types.
-}
key11Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key11Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 itemType10 itemType11 =
    Reference attributes (toFQName moduleName "Key11") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9, itemType10, itemType11 ]


{-| Create a type key with 12 types.
-}
key12Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key12Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 itemType10 itemType11 itemType12 =
    Reference attributes (toFQName moduleName "Key12") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9, itemType10, itemType11, itemType12 ]


{-| Create a type key with 13 types.
-}
key13Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key13Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 itemType10 itemType11 itemType12 itemType13 =
    Reference attributes (toFQName moduleName "Key13") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9, itemType10, itemType11, itemType12, itemType13 ]


{-| Create a type key with 14 types.
-}
key14Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key14Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 itemType10 itemType11 itemType12 itemType13 itemType14 =
    Reference attributes (toFQName moduleName "Key14") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9, itemType10, itemType11, itemType12, itemType13, itemType14 ]


{-| Create a type key with 15 types.
-}
key15Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key15Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 itemType10 itemType11 itemType12 itemType13 itemType14 itemType15 =
    Reference attributes (toFQName moduleName "Key15") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9, itemType10, itemType11, itemType12, itemType13, itemType14, itemType15 ]


{-| Create a type key with 16 types.
-}
key16Type : a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a -> Type a
key16Type attributes itemType1 itemType2 itemType3 itemType4 itemType5 itemType6 itemType7 itemType8 itemType9 itemType10 itemType11 itemType12 itemType13 itemType14 itemType15 itemType16 =
    Reference attributes (toFQName moduleName "Key16") [ itemType1, itemType2, itemType3, itemType4, itemType5, itemType6, itemType7, itemType8, itemType9, itemType10, itemType11, itemType12, itemType13, itemType14, itemType15, itemType16 ]



--# Generating this module
--
--This module was generated by the below snippet. You can use it to generate higher element values or other features
--if needed.
--gen : Int -> String
--gen maxIndex =
--    let
--        genKeyType : Int -> String
--        genKeyType n =
--            "( Name.fromString \"Key" ++ String.fromInt n ++ "\", OpaqueTypeSpecification [] |> Documented \"\" )"
--
--        genValueType : Int -> String
--        genValueType n =
--            let
--                argValues =
--                    "vSpec \"key"
--                        ++ String.fromInt n
--                        ++ "\"\n"
--                        ++ "                [ "
--                        ++ (List.range 1 n
--                                |> List.map
--                                    (\i ->
--                                        "( \"getKey"
--                                            ++ String.fromInt i
--                                            ++ "\", tFun [ tVar \"a\" ] (tVar \"b"
--                                            ++ String.fromInt i
--                                            ++ "\") )"
--                                    )
--                                |> String.join "\n                , "
--                           )
--
--                attributes =
--                    case n of
--                        0 ->
--                            ""
--
--                        _ ->
--                            "\n                , ( \"a\", tVar \"a\" )"
--
--                returnTypes =
--                    "\n                ]\n "
--                        ++ "                (key"
--                        ++ String.fromInt n
--                        ++ "Type ()"
--                        ++ (List.range 1 n
--                                |> List.map
--                                    (\i ->
--                                        "\n                   ( tVar "
--                                            ++ "\"b"
--                                            ++ String.fromInt i
--                                            ++ "\" )"
--                                    )
--                                |> String.join ""
--                           )
--                        ++ "\n                 )"
--            in
--            argValues ++ attributes ++ returnTypes
--
--        genKeyFun : Int -> String
--        genKeyFun n =
--            let
--                funName =
--                    "key" ++ String.fromInt n ++ "Type"
--
--                argTypes =
--                    List.range 1 n
--                        |> List.map (\i -> " -> Type a")
--                        |> String.join " "
--
--                argNames =
--                    List.range 1 n
--                        |> List.map (\i -> "itemType" ++ String.fromInt i)
--                        |> String.join " "
--
--                body keys =
--                    " (toFQName moduleName \"Key"
--                        ++ String.fromInt n
--                        ++ "\") ["
--                        ++ (List.range 1 n
--                                |> List.map (\i -> "itemType" ++ String.fromInt i)
--                                |> String.join ", "
--                           )
--                        ++ "]"
--            in
--            String.join "\n"
--                [ "{-| Create a type key with " ++ String.fromInt n ++ " types."
--                , "-}"
--                , funName ++ " : a" ++ argTypes ++ " -> Type a"
--                , funName ++ " attributes " ++ argNames ++ " ="
--                , "    Reference attributes" ++ body (List.range 1 n)
--                ]
--    in
--    String.join "\n\n\n"
--        [ String.join "\n"
--            [ "module Morphir.IR.SDK.Key exposing (..)"
--            , "import Dict exposing (Dict)"
--            , ""
--            , "import Morphir.IR.Documented exposing (Documented)"
--            , "import Morphir.IR.Module as Module exposing (ModuleName)"
--            , "import Morphir.IR.Name as Name exposing (Name)"
--            , "import Morphir.IR.Path as Path exposing (Path)"
--            , "import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)"
--            , "import Morphir.IR.Type exposing (Specification(..), Type(..))"
--            , ""
--            , "moduleName : ModuleName"
--            , "moduleName ="
--            , """   Path.fromString "Key" """
--            , ""
--            , "moduleSpec : Module.Specification ()"
--            , "moduleSpec ="
--            , "    { types ="
--            , "        Dict.fromList"
--            , "            [ "
--                ++ genKeyType 0
--                ++ "\n            , "
--                ++ (List.range 2 maxIndex |> List.map (\n -> genKeyType n) |> String.join "\n            , ")
--            , "            ]"
--            , "    , values ="
--            , "        Dict.fromList"
--            , "            [ "
--                ++ "vSpec \"noKey\" [] (key0Type ())\n"
--                ++ "            , "
--                ++ genValueType 0
--                ++ "\n            , "
--                ++ (List.range 2 maxIndex |> List.map (\n -> genValueType n) |> String.join "\n            ,")
--            , "            ]"
--            , "    }"
--            ]
--        , genKeyFun 0
--        , List.range 2 maxIndex
--            |> List.map genKeyFun
--            |> String.join "\n\n\n"
--        ]
