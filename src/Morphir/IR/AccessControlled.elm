module Morphir.IR.AccessControlled exposing
    ( AccessControlled(..)
    , public, private
    , withPublicAccess, withPrivateAccess
    , decodeAccessControlled, encodeAccessControlled
    , map
    )

{-| Module to manage access to a node in the IR. This is only used to declare access levels
not to enforce them. Enforcement can be done through the helper functions
[withPublicAccess](#withPublicAccess) and [withPrivateAccess](#withPrivateAccess) but it's
up to the consumer of the API to call the righ function.

@docs AccessControlled


# Creation

@docs public, private


# Query

@docs withPublicAccess, withPrivateAccess


# Serialization

@docs decodeAccessControlled, encodeAccessControlled

-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| Type that represents different access levels.
-}
type AccessControlled a
    = Public a
    | Private a


{-| Mark a node as public access. Actors with both public and private access are allowed to see.
-}
public : a -> AccessControlled a
public value =
    Public value


{-| Mark a node as private access. Only actors with private access level can see.
-}
private : a -> AccessControlled a
private value =
    Private value


{-| Get the value with public access level. Will return `Nothing` if the value is private.

    withPublicAccess (public 13) -- Just 13

    withPublicAccess (private 13) -- Nothing

-}
withPublicAccess : AccessControlled a -> Maybe a
withPublicAccess ac =
    case ac of
        Public a ->
            Just a

        Private a ->
            Nothing


{-| Get the value with private access level. Will always return the value.

    withPrivateAccess (public 13) -- 13

    withPrivateAccess (private 13) -- 13

-}
withPrivateAccess : AccessControlled a -> a
withPrivateAccess ac =
    case ac of
        Public a ->
            a

        Private a ->
            a


map : (a -> b) -> AccessControlled a -> AccessControlled b
map f ac =
    case ac of
        Public a ->
            Public (f a)

        Private a ->
            Private (f a)


{-| Encode AccessControlled to JSON.
-}
encodeAccessControlled : (a -> Encode.Value) -> AccessControlled a -> Encode.Value
encodeAccessControlled encodeValue ac =
    case ac of
        Public value ->
            Encode.object
                [ ( "$type", Encode.string "public" )
                , ( "value", encodeValue value )
                ]

        Private value ->
            Encode.object
                [ ( "$type", Encode.string "private" )
                , ( "value", encodeValue value )
                ]


{-| Decode AccessControlled from JSON.
-}
decodeAccessControlled : Decode.Decoder a -> Decode.Decoder (AccessControlled a)
decodeAccessControlled decodeValue =
    Decode.field "$type" Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "public" ->
                        Decode.map Public
                            (Decode.field "value" decodeValue)

                    "private" ->
                        Decode.map Private
                            (Decode.field "value" decodeValue)

                    other ->
                        Decode.fail <| "Unknown access controlled type: " ++ other
            )
