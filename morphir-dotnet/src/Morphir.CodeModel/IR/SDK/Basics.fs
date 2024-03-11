module Morphir.IR.SDK.Basics

open System
open Morphir.IR
open Morphir.SDK
open Morphir.SDK.Maybe
open Morphir.IR.Module
open Morphir.IR.Documented
open Morphir.IR.FQName
open Morphir.IR.Name
open Morphir.IR.Path
open Morphir.IR.Type
open Morphir.IR.SDK.Common

let moduleName: ModuleName = Path.fromString "Basics"

let encodeOrder (order: Order) : Value.Value<'a, unit> =
    let value =
        match order with
        | LT -> "LT"
        | EQ -> "EQ"
        | GT -> "GT"

    Value.Constructor((), toFQName moduleName value)

let inline orderType (attributes: 'a) : Type<'a> =
    Reference(attributes, (toFQName moduleName "Order"), [])

let inline neverType (attributes: 'a) : Type<'a> =
    Reference(attributes, (toFQName moduleName "Never"), [])

let inline equal (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "equal"))

let inline notEqual (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "notEqual"))

let boolType (attributes: 'a) : Type<'a> =
    Reference(attributes, (toFQName moduleName "Bool"), [])

let ``and`` (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "and"))

let ``or`` (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "or"))

let negate (refAttributes: 'a) (valueAttributes: 'a) (arg: Value.Value<'b, 'a>) : Value.Value<'b, 'a> =
    Value.Apply(valueAttributes, Value.Reference(refAttributes, (toFQName moduleName "negate")), arg)

let add attributes =
    Value.Reference(attributes, (toFQName moduleName "add"))

let subtract attributes =
    Value.Reference(attributes, (toFQName moduleName "subtract"))

let multiply attributes =
    Value.Reference(attributes, (toFQName moduleName "multiply"))

let power attributes =
    Value.Reference(attributes, (toFQName moduleName "power"))

let inline intType (attributes: 'a) : Type<'a> =
    Reference(attributes, (toFQName moduleName "Int"), [])

let integerDivide (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "integerDivide"))

let inline floatType attributes : Type<'a> =
    Reference(attributes, (toFQName moduleName "Float"), [])

let divide (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "divide"))

let lessThan (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "lessThan"))

let lessThanOrEqual (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "lessThanOrEqual"))

let greaterThan (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "greaterThan"))

let greaterThanOrEqual (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "greaterThanOrEqual"))

let composeLeft (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "composeLeft"))

let composeRight (attributes: 'a) : Value.Value<'b, 'a> =
    Value.Reference(attributes, (toFQName moduleName "composeRight"))

let isNumber =
    function
    | Reference(_,
                FQName(PathSegments([ [ "morphir" ]; [ "s"; "d"; "k" ] ]),
                       PathSegments([ [ "basics" ] ]),
                       NameParts([ "float" ])),
                []) -> true
    | Reference(_,
                FQName(PathSegments([ [ "morphir" ]; [ "s"; "d"; "k" ] ]),
                       PathSegments([ [ "basics" ] ]),
                       NameParts([ "int" ])),
                []) -> true
    | _ -> false


let moduleSpec: Module.Specification<unit> =
    { Types =
        Dict.fromList
            [ namedTypeSpec "Int" (OpaqueTypeSpecification []) "Type that represents an integer value."
              namedTypeSpec "Float" (OpaqueTypeSpecification []) "Type that represents a floating-point number."
              namedTypeSpec
                  "Order"
                  (Dict.fromList [ Name.fromString "LT", []; Name.fromString "EQ", []; Name.fromString "GT", [] ]
                   |> customTypeSpecification [])
                  "Represents the relative ordering of two things. The relations are less than, equal to, and greater than."
              namedTypeSpec "Bool" (OpaqueTypeSpecification []) "Type that represents a boolean value."
              namedTypeSpec "Never" (OpaqueTypeSpecification []) "A value that can never happen!" ]
      Values =
        Dict.fromList
            [
              // number
              vSpec "add" [ ("a", tVar "number"); ("b", tVar "number") ] (tVar "number")
              vSpec "subtract" [ ("a", tVar "number"); ("b", tVar "number") ] (tVar "number")
              vSpec "multiply" [ ("a", tVar "number"); ("b", tVar "number") ] (tVar "number")
              vSpec "divide" [ ("a", floatType ()); ("b", floatType ()) ] (floatType ())
              // Bool
              vSpec "not" [ ("a", boolType ()) ] (boolType ())
              vSpec "and" [ ("a", boolType ()); ("b", boolType ()) ] (boolType ())
              vSpec "or" [ ("a", boolType ()); ("b", boolType ()) ] (boolType ())
              vSpec "xor" [ ("a", boolType ()); ("b", boolType ()) ] (boolType ())
              // appendable
              vSpec "append" [ ("a", tVar "appendable"); ("b", tVar "appendable") ] (tVar "appendable") ]
      Doc = Just "Types and functions representing basic mathematical concepts and operations" }
