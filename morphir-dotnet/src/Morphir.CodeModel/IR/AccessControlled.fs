/// Module to manage access to a node in the IR. This is only used to declare access levels
/// not to enforce them. Enforcement can be done through the helper functions
/// [withPublicAccess](#withPublicAccess) and [withPrivateAccess](#withPrivateAccess) but it's
/// up to the consumer of the API to call the right function.
module Morphir.IR.AccessControlled

open Morphir.SDK.Maybe

/// <summary>
/// Type that represents different access levels.
/// </summary>
type AccessControlled<'a> = { Access: Access; Value: 'a }

/// <summary>
/// Public or private access.
/// </summary>
and Access =
    | Public
    | Private

let accessControlled access value = { Access = access; Value = value }

/// Mark a node as public access. Actors with both public and private access are allowed to see.
let inline ``public`` value = { Access = Public; Value = value }

/// Mark a node as private access. Only actors with private access level can see.
let inline ``private`` value = { Access = Private; Value = value }

/// Mark a node as public access. Actors with both public and private access are allowed to see.
let inline mkPublic value = { Access = Public; Value = value }

/// Mark a node as private access. Only actors with private access level can see.
let inline mkPrivate value = { Access = Private; Value = value }

///  Get the value with public access level. Will return `Nothing` if the value is private.
let withPublicAccess ac =
    match ac.Access with
    | Public -> Just ac.Value
    | Private -> Nothing

/// Get the value with private access level. Will always return the value.
let withPrivateAccess ac =
    match ac.Access with
    | Public -> ac.Value
    | Private -> ac.Value

// Get the value with public or private access level. Will return `Nothing` if the value is private
// and accessed using public access.
let withAccess access ac =
    match access with
    | Public -> withPublicAccess ac
    | Private -> Just(withPrivateAccess ac)

let map (f: 'a -> 'b) (ac: AccessControlled<'a>) : AccessControlled<'b> = {
    Access = ac.Access
    Value = f (ac.Value)
}
