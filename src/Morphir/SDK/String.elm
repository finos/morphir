module Morphir.SDK.String exposing (ofLength, ofMaxLength)

{-| Utilities to extends the basic String operations provided by `elm/core`.


# Constraints

Constraints provide a way to add value level constraints to types that are stored as Strings. While the Elm compiler
doesn't support checking such constraints statically we can use the information in Morphir backends to generate more
specific types. For example given the below definition:

    type alias Trade =
        { productID : Cusip
        , comment : Maybe Comment
        }

    type Cusip
        = Cusip String

    cusip =
        String.ofLength 9 Cusip

    type Comment
        = Comment String

    comment =
        String.ofMaxLength 100 Comment

We can generate the following DDL in our relational backend:

```sql
CREATE TABLE
    trade
    ( product_id CHAR 9 NOT NULL
    , comment VARCHAR 100 NULL
    )
```

@docs ofLength, ofMaxLength

-}


{-| Checks the exact length of a string and wraps it using the specified constructor.

    currency =
        String.ofLength 3 Currency

    currency "USD" == Just (Currency "USD")
    currency "us" == Nothing
    currency "LONG" == Nothing

-}
ofLength : Int -> (String -> a) -> String -> Maybe a
ofLength length ctor value =
    if String.length value == length then
        Just (ctor value)

    else
        Nothing


{-| Checks the max length of a string and wraps it using the specified constructor.

    name =
        String.ofMaxLength 15 Name

    name "" == Just (Name "")
    name "A name" == Just (Name "")
    name "A very long name" == Nothing

-}
ofMaxLength : Int -> (String -> a) -> String -> Maybe a
ofMaxLength maxLength ctor value =
    if String.length value <= maxLength then
        Just (ctor value)

    else
        Nothing

{-| Checks to see if two strings are equal ignore case

    isEqual =
        String.equalIgnoreCase "HeLlO" "Hello"

    isEqual == True
-}
equalIgnoreCase : String -> String -> Bool
equalIgnoreCase str1 str2 =
   if not ((String.length str1) == (String.length str2)) then
        False
   else
        (String.toLower str1)  == (String.toLower str2)
