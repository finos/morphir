module Morphir.SDK.UUID exposing (
    UUID
    , Error(..)
    , parse
    , fromString
    , forName
    , toString
    , version
    , compare
    , nilString
    , isNilString
    , dnsNamespace
    , urlNamespace
    , oidNamespace
    , x500Namespace) 

{-|
    # The datatype

    @docs UUID
    @docs Error


    # Convert from a known UUID String

    @docs parse
    @docs fromString


    # Create

    @docs forName


    # Convert to

    @docs toString

    
    # Comparing

    @docs compare


    # Nil check

    @docs isNilString


    # Nil UUID

    @docs nilString


    # Namespaces

    @docs dnsNamespace
    @docs urlNamespace
    @docs oidNamespace
    @docs x500Namespace


    # Other misc functions

    @docs version

-}

import UUID as U

{-| The UUID datatype -}
type alias UUID = 
    U.UUID

{-| The error type for UUIDs -}
type  Error
    = WrongFormat
    | WrongLength
    | UnsupportedVariant
    | IsNil
    | NoVersion


{-| You can attempt to create a UUID from a string. This function can interpret a fairly broad range of formatted (and mis-formatted) UUIDs, including ones with too much whitespace, too many (or not enough) hyphens, or uppercase characters.-}
parse : String -> Result Error UUID
parse s = 
    U.fromString s
    |> Result.mapError fromUUIDError

{-| Includes all the functionality as `parse`, however only returns a `Maybe` on failures instead of an `Error`.-}
fromString : String -> Maybe UUID
fromString s = 
    U.fromString s |> Result.toMaybe


{-| Create a version 5 UUID from a String and a namespace, which should be a UUID. The same name and namespace will always produce the same UUID, which can be used to your advantage. Furthermore, the UUID created from this can be used as a namespace for another UUID, creating a hierarchy of sorts.-}
forName : String -> UUID -> UUID
forName s uuid =
    U.forName s uuid


{-| The cannonical representation of the UUID -}
toString : UUID -> String
toString uuid = 
    U.toString uuid


{-| Get the version number of a UUID. Only versions 3, 4, and 5 are supported in this package, so you should expect the returned Int to be 3, 4, or 5.-}
version : UUID -> Int
version uuid =
    U.version uuid

{-| Returns the relative ordering of two UUIDs. THe main use case of this function is helping in binary-searching algorithms. Mimics elm/core's compare.-}
compare : UUID -> UUID -> Order
compare uuid1 uuid2 =
    U.compare uuid1 uuid2


{-| Returns a nil UUID.-}
nilString : String
nilString = 
    U.nilString

{-| True if the given string represents the nil UUID (00000000-0000-0000-0000-000000000000).-}
isNilString : String -> Bool
isNilString s = 
    U.isNilString s

{-| A UUID for the DNS namespace, "6ba7b810-9dad-11d1-80b4-00c04fd430c8".-}
dnsNamespace : UUID
dnsNamespace =
    U.dnsNamespace


{-| A UUID for the URL namespace, "6ba7b811-9dad-11d1-80b4-00c04fd430c8".-}
urlNamespace : UUID
urlNamespace =
    U.urlNamespace

{-| A UUID for the ISO object ID (OID) namespace, "6ba7b812-9dad-11d1-80b4-00c04fd430c8".-}
oidNamespace : UUID
oidNamespace = 
    U.oidNamespace

{-| A UUID for the X.500 Distinguished Name (DN) namespace, "6ba7b814-9dad-11d1-80b4-00c04fd430c8".-}
x500Namespace : UUID
x500Namespace = 
    U.x500Namespace

fromUUIDError : U.Error -> Error
fromUUIDError e =
    case e of
        U.WrongFormat -> WrongFormat
        U.WrongLength -> WrongLength
        U.UnsupportedVariant -> UnsupportedVariant
        U.IsNil -> IsNil
        U.NoVersion -> NoVersion