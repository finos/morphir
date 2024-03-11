module Morphir.IR.SDK.String

open Morphir.IR
open Morphir.SDK
open Morphir.SDK.Maybe
open Morphir.IR.SDK.Common
open Morphir.IR.Type

let moduleName = Path.fromString "String"

let moduleSpec: Module.Specification<unit> = {
    Types = Dict.fromList []
    Values = Dict.fromList []
    Doc = Just "Contains the String type, and related functions."
}

let stringType attributes : Type<'a> =
    reference attributes (toFQName moduleName "String") []
