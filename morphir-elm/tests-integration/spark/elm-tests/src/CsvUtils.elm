{-
   Copyright 2022 Morgan Stanley

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


module CsvUtils exposing (..)

import Csv.Decode as Decode exposing (..)
import Csv.Encode as Encode exposing (..)
import SparkTests.DataDefinition.Field.Category exposing (Category(..), categoryFromString, categoryToString)
import SparkTests.DataDefinition.Field.Report exposing (FeedBack(..), feedBackFromString, feedBackToString)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..), productFromString, productToString)
import SparkTests.Types exposing (AntiqueSubset)


boolFromString : String -> Result String Bool
boolFromString str =
    if String.isEmpty str then
        Err "Empty strings are not valid Boolean strings."

    else
        case str of
            "True" ->
                True |> Ok

            "False" ->
                False |> Ok

            _ ->
                Err "Invalid Boolean string."


boolToString : Bool -> String
boolToString bool =
    case bool of
        True ->
            "True"

        False ->
            "False"


decodeProduct : Decoder Product
decodeProduct =
    andThen
        (\value -> fromResult (productFromString value))
        Decode.string


decodeCategory : Decoder Category
decodeCategory =
    Decode.string
        |> andThen (\value -> fromResult (categoryFromString value))


decodeFeedBack : Decoder FeedBack
decodeFeedBack =
    Decode.string
        |> andThen (\value -> fromResult (feedBackFromString value))


decodeBool : Decoder Bool
decodeBool =
    Decode.string
        |> andThen (\value -> fromResult (boolFromString value))


antiqueDecoder : Decoder Antique
antiqueDecoder =
    Decode.into Antique
        |> Decode.pipeline (Decode.field "category" (Decode.blank decodeCategory))
        |> Decode.pipeline (Decode.field "product" decodeProduct)
        |> Decode.pipeline (Decode.field "priceValue" Decode.float)
        |> Decode.pipeline (Decode.field "ageOfItem" Decode.float)
        |> Decode.pipeline (Decode.field "handMade" decodeBool)
        |> Decode.pipeline (Decode.field "requiresExpert" decodeBool)
        |> Decode.pipeline (Decode.field "expertFeedBack" (Decode.blank decodeFeedBack))
        |> Decode.pipeline (Decode.field "report" (Decode.blank Decode.string))


antiqueEncoder : List Antique -> String
antiqueEncoder antiques =
    antiques
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\antique ->
                        [ ( "category", categoryToString antique.category )
                        , ( "product", productToString antique.product )
                        , ( "priceValue", String.fromFloat antique.priceValue )
                        , ( "ageOfItem", String.fromFloat antique.ageOfItem )
                        , ( "handMade", boolToString antique.handMade )
                        , ( "requiresExpert", boolToString antique.requiresExpert )
                        , ( "expertFeedback", feedBackToString antique.expertFeedback )
                        , ( "report", antique.report |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }


antiqueSSDecoder : Decoder AntiqueSubset
antiqueSSDecoder =
    Decode.into AntiqueSubset
        |> Decode.pipeline (Decode.field "name" Decode.string)
        |> Decode.pipeline (Decode.field "ageOfItem" Decode.float)
        |> Decode.pipeline (Decode.field "product" decodeProduct)
        |> Decode.pipeline (Decode.field "report" (Decode.blank Decode.string))


antiqueSSEncoder : List AntiqueSubset -> String
antiqueSSEncoder antiqueSubsets =
    antiqueSubsets
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\antiqueSubset ->
                        [ ( "name", antiqueSubset.name )
                        , ( "ageOfItem", String.fromFloat antiqueSubset.ageOfItem )
                        , ( "product", productToString antiqueSubset.product )
                        , ( "report", antiqueSubset.report |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias AgeRecord =
    { ageOfItem : Float }


antiqueAgeDecoder : Decoder AgeRecord
antiqueAgeDecoder =
    Decode.into AgeRecord
        |> Decode.pipeline (Decode.field "ageOfItem" Decode.float)


antiqueAgeEncoder : List AgeRecord -> String
antiqueAgeEncoder ages =
    ages
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\age ->
                        [ ( "ageOfItem", String.fromFloat age.ageOfItem )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias NameRecord =
    { name : String }


antiqueNameDecoder : Decoder NameRecord
antiqueNameDecoder =
    Decode.into NameRecord
        |> Decode.pipeline (Decode.field "name" Decode.string)


antiqueNameEncoder : List NameRecord -> String
antiqueNameEncoder names =
    names
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\name1 ->
                        [ ( "name", name1.name )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias ProductRecord =
    { product : Product }


antiqueProductDecoder : Decoder ProductRecord
antiqueProductDecoder =
    Decode.into ProductRecord
        |> Decode.pipeline (Decode.field "product" decodeProduct)


antiqueProductEncoder : List ProductRecord -> String
antiqueProductEncoder products =
    products
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\product1 ->
                        [ ( "product", productToString product1.product )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooString =
    { foo : String }


fooStringDecoder : Decoder FooString
fooStringDecoder =
    Decode.into FooString
        |> Decode.pipeline (Decode.field "foo" Decode.string)


fooStringEncoder : List FooString -> String
fooStringEncoder strings =
    strings
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\string ->
                        [ ( "foo", string.foo )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooBool =
    { foo : Bool }


fooBoolDecoder : Decoder FooBool
fooBoolDecoder =
    Decode.into FooBool
        |> Decode.pipeline (Decode.field "foo" decodeBool)


fooBoolEncoder : List FooBool -> String
fooBoolEncoder bools =
    bools
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\bool ->
                        [ ( "foo", boolToString bool.foo )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooInt =
    { foo : Int }


fooIntDecoder : Decoder FooInt
fooIntDecoder =
    Decode.into FooInt
        |> Decode.pipeline (Decode.field "foo" Decode.int)


fooIntEncoder : List FooInt -> String
fooIntEncoder ints =
    ints
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\int ->
                        [ ( "foo", String.fromInt int.foo )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooFloat =
    { foo : Float }


fooFloatDecoder : Decoder FooFloat
fooFloatDecoder =
    Decode.into FooFloat
        |> Decode.pipeline (Decode.field "foo" Decode.float)


fooFloatEncoder : List FooFloat -> String
fooFloatEncoder floats =
    floats
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\float ->
                        [ ( "foo", String.fromFloat float.foo )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooMaybeBool =
    { foo : Maybe Bool }


fooBoolMaybeDecoder : Decoder FooMaybeBool
fooBoolMaybeDecoder =
    Decode.into FooMaybeBool
        |> Decode.pipeline (Decode.field "foo" (Decode.blank decodeBool))


fooBoolMaybeEncoder : List FooMaybeBool -> String
fooBoolMaybeEncoder bools =
    bools
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\bool ->
                        [ ( "foo", bool.foo |> Maybe.map boolToString |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooMaybeString =
    { foo : Maybe String }


fooStringMaybeDecoder : Decoder FooMaybeString
fooStringMaybeDecoder =
    Decode.into FooMaybeString
        |> Decode.pipeline (Decode.field "foo" (Decode.blank Decode.string))


fooStringMaybeEncoder : List FooMaybeString -> String
fooStringMaybeEncoder strings =
    strings
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\string ->
                        [ ( "foo", string.foo |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooMaybeInt =
    { foo : Maybe Int }


fooIntMaybeDecoder : Decoder FooMaybeInt
fooIntMaybeDecoder =
    Decode.into FooMaybeInt
        |> Decode.pipeline (Decode.field "foo" (Decode.blank Decode.int))


fooIntMaybeEncoder : List FooMaybeInt -> String
fooIntMaybeEncoder ints =
    ints
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\int ->
                        [ ( "foo", int.foo |> Maybe.map String.fromInt |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }


type alias FooMaybeFloat =
    { foo : Maybe Float }


fooFloatMaybeDecoder : Decoder FooMaybeFloat
fooFloatMaybeDecoder =
    Decode.into FooMaybeFloat
        |> Decode.pipeline (Decode.field "foo" (Decode.blank Decode.float))


fooFloatMaybeEncoder : List FooMaybeFloat -> String
fooFloatMaybeEncoder floats =
    floats
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\float ->
                        [ ( "foo", float.foo |> Maybe.map String.fromFloat |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }



encodeProductList : List Product -> String
encodeProductList result =
    result
        |> List.map productToString
        |> (::) "product"
        |> String.join "\u{000D}\n"


encodeFloatList : List Float -> String
encodeFloatList result =
    result
        |> List.map String.fromFloat
        |> (::) "float"
        |> String.join "\u{000D}\n"


encodeMinSumRecord : { sum : Float, min : Maybe Float } -> String
encodeMinSumRecord record =
    "min,sum\r\n" ++ ( record.min |> Maybe.map String.fromFloat |> Maybe.withDefault "" ) ++ "," ++ (String.fromFloat record.sum)
