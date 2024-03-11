[<AutoOpen>]
module Morphir.IR.SDK.Common

open Morphir.IR.Documented
open Morphir.IR.Name
open Morphir.IR.Package
open Morphir.IR.Module
open Morphir.IR.Value
open Morphir.IR.Type
open Morphir.IR
open Morphir.SDK.List

let packageName: PackageName = PackageName.fromString "Morphir.SDK"

let toFQName (modulePath: Path.Path) (localName: string) : FQName.FQName =
    localName
    |> Name.fromString
    |> QName.fromName modulePath
    |> FQName.fromQName (PackageName.toPath packageName)

let binaryApply
    (moduleName: ModuleName)
    (localName: string)
    (attributes: 'va)
    (arg1: Value<'ta, 'va>)
    (arg2: Value<'ta, 'va>)
    : Value<'ta, 'va> =
    Value.Apply(
        attributes,
        Value.Apply(attributes, Value.Reference(attributes, toFQName moduleName localName), arg1),
        arg2
    )

let tVar (varName: string) : Type<unit> =
    Type.variable () (Name.fromString varName)

let namedTypeSpec
    (name: string)
    (spec: Type.Specification<'a>)
    (doc: string)
    : Name * Documented<Type.Specification<'a>> =
    (Name.fromString name, spec |> documented doc)

let tFun (argTypes: Type<unit> list) (returnType: Type<unit>) : Type<unit> =
    let rec curry args =
        match args with
        | [] -> returnType
        | arg :: rest -> Type.Function((), arg, curry rest)

    curry argTypes

let vSpec
    (name: string)
    (args: List<string * Type<unit>>)
    (returnType: Type<unit>)
    : Name * Documented<Value.Specification<unit>> =
    (Name.fromString name,
     specification (args |> List.map (fun (argName, argType) -> (Name.fromString argName, argType))) returnType
     |> documented "documentation")
