module rec Morphir.IR.Type

open System
open Morphir.Extensions
open Morphir.Pattern
open Morphir.IR.AccessControlled
open Morphir.IR.Name
open Morphir.IR.FQName
open Morphir.SDK.Dict
open Morphir.SDK.Maybe
open Morphir.IR
open Morphir.SDK

type Type<'A> =
    | Variable of Attributes: 'A * Name: Name
    | Reference of Attributes: 'A * TypeName: FQName * TypeParameters: Type<'A> list
    | Tuple of Attributes: 'A * ElementTypes: Type<'A> list
    | Record of Attributes: 'A * FieldTypes: Field<'A> list
    | ExtensibleRecord of Attributes: 'A * VariableName: Name * FieldTypes: Field<'A> list
    | Function of Attributes: 'A * ArgumentType: Type<'A> * ReturnType: Type<'A>
    | Unit of Attributes: 'A

    member this.Attributes =
        match this with
        | Variable(a, _) -> a
        | Reference(a, _, _) -> a
        | Tuple(a, _) -> a
        | Record(a, _) -> a
        | ExtensibleRecord(a, _, _) -> a
        | Function(a, _, _) -> a
        | Unit a -> a

    interface Expression<'A> with
        member this.Attributes = this.Attributes

type Field<'A> = { Name: Name; Type: Type<'A> }

type Constructors<'A> = Dict<Name, ConstructorArgs<'A>>

and Constructors =
    static member Create([<ParamArray>] constructors: (Name * ConstructorArgs<'A>) array) : Constructors<'A> =
        constructors |> List.ofArray |> Dict.fromList

    static member Create([<ParamArray>] constructors: (String * ConstructorArgs<'A>) array) : Constructors<'A> =
        constructors
        |> List.ofArray
        |> List.map (fun (name, args) -> Name.fromString name, args)
        |> Dict.fromList

    static member Empty<'A>() : Constructors<'A> = empty

type Constructor<'a> = Name * ConstructorArgs<'a>

and Constructor =
    static member Create(name, args) : Constructor<'a> = (name, args)

    static member Create(name: string, [<ParamArray>] args: (string * Type<'a>) array) : Constructor<'a> =
        (Name.fromString name, ConstructorArgs.Create(args))

and ConstructorArgs<'a> = List<Name * Type<'a>>

and ConstructorArgs =
    static member Create([<ParamArray>] args: (Name * Type<'a>) array) : ConstructorArgs<'a> = args |> List.ofArray

    static member Create([<ParamArray>] args: (string * Type<'a>) array) : ConstructorArgs<'a> =
        args |> List.ofArray |> List.map (fun (name, typ) -> Name.fromString name, typ)

/// <summary>
/// Represents the specification (in other words the interface) of a type. There are 4 different shapes:
/// <see cref="TypeAliasSpecification"/>, <see cref="OpaqueTypeSpecification"/>, <see cref="CustomTypeSpecification"/>, and <see cref="DerivedTypeSpecification"/>.
/// </summary>
type Specification<'A> =
    /// <summary>
    /// Represents an alias for another type.
    /// </summary>
    /// <example>
    /// <code>
    /// type Foo = String
    /// </code>
    /// </example>
    | TypeAliasSpecification of TypeParams: Name list * TypeExpr: Type<'A>
    /// Represents a type with an unknown structure.
    /// In Elm you could achieve this with a custom type that doesn't expose its constructors.
    | OpaqueTypeSpecification of TypeParams: Name list
    | CustomTypeSpecification of TypeParams: Name list * Constructors: Constructors<'A>
    | DerivedTypeSpecification of TypeParams: Name list * MappingInfo: DerivedTypeMappingInfo<'A>

and Specification =
    static member Custom(typeParams, constructors) =
        let typeParams = typeParams |> List.map Name.fromString

        CustomTypeSpecification(typeParams, constructors)

    static member Custom(typeParams, [<ParamArray>] constructors: (Name * ConstructorArgs<'A>) array) =
        let typeParams = typeParams |> List.map Name.fromString

        CustomTypeSpecification(typeParams, Constructors.Create constructors)

and DerivedTypeMappingInfo<'A> =
    { BaseType: Type<'A>
      FromBaseType: FQName
      ToBaseType: FQName }

and Definition<'A> =
    | TypeAliasDefinition of TypeParams: Name list * TypeExpr: Type<'A>
    | CustomTypeDefinition of TypeParams: Name list * Constructors: AccessControlled<Constructors<'A>>

type Field<'A> with

    member this.MapName f = { this with Name = f (this.Name) }

    member this.MapType f =
        { Name = this.Name
          Type = f (this.Type) }

let fold<'Attrib, 'State> (folder: 'State -> Type<'Attrib> -> 'State) (state: 'State) (typ: Type<'Attrib>) : 'State =
    match typ with
    | Unit _ as t -> folder state t
    | Variable _ as t -> folder state t
    | Reference _ as t -> folder state t
    | Tuple(_, elems) as t ->
        let state = elems |> List.fold folder state

        folder state t
    | Record(_, fields) as t ->
        let state = fields |> List.fold (fun state field -> folder state field.Type) state

        folder state t
    | ExtensibleRecord(_, _, fields) as t ->
        let state = fields |> List.fold (fun state field -> folder state field.Type) state

        folder state t
    | Function(_, argType, returnType) as t ->
        let state = folder state argType
        let state = folder state returnType
        folder state t


/// Get a compact string representation of the type.
[<CompiledName("ToString")>]
let toString tpe =
    stringBuffer {
        match tpe with
        | Unit _ -> yield "()"
        | Variable(_, name) -> yield name |> Name.toCamelCase
        | Reference(_, fqName, typeParameters) ->
            yield fqName |> FQName.toReferenceName

            for typeStr in typeParameters do
                yield " "

                yield typeStr |> toString
        | Tuple(_, elements) ->
            yield "("

            for (index, t) in (elements |> List.mapi (fun index t -> index, t)) do
                if index > 0 then
                    yield ", "

                yield t |> toString

            yield ")"
        | Record(_, fields) ->
            yield "{ "

            for (index, field) in (fields |> List.mapi (fun index field -> index, field)) do
                if index > 0 then
                    yield ", "

                yield field.Name |> Name.toCamelCase

                yield " : "

                yield field.Type |> toString

            yield " }"
        | ExtensibleRecord(_, variableName, fields) ->
            yield $"{{ {Name.toCamelCase variableName} | "

            for (index, field) in (fields |> List.mapi (fun index field -> index, field)) do
                if index > 0 then
                    yield ", "

                yield field.Name |> Name.toCamelCase

                yield " : "

                yield field.Type |> toString

            yield " }"
        | Function(_, (Function(_, _, _) as argType), returnType) ->
            yield $"({argType |> toString}) -> {returnType |> toString}"
        | Function(_, argType, returnType) -> yield $"{argType |> toString} -> {returnType |> toString}"
    }

let inline typeAliasDefinition typeParams typeExp =
    TypeAliasDefinition(typeParams, typeExp)

let inline customTypeDefinition typeParams ctors = CustomTypeDefinition(typeParams, ctors)

let inline typeAliasSpecification typeParams typeExp =
    TypeAliasSpecification(typeParams, typeExp)

let inline opaqueTypeSpecification typeParams = OpaqueTypeSpecification typeParams

let inline customTypeSpecification typeParams ctors =
    CustomTypeSpecification(typeParams, ctors)

let inline derivedTypeSpecification typeParams mappingInfo =
    DerivedTypeSpecification(typeParams, mappingInfo)

let inline reference attributes typeName typeParameters =
    Reference(attributes, typeName, typeParameters)

let inline tuple attributes elementTypes = Tuple(attributes, elementTypes)
let inline record attributes fieldTypes = Record(attributes, fieldTypes)


let definitionToSpecification (def: Definition<'A>) : Specification<'A> =
    match def with
    | TypeAliasDefinition(p, exp) -> TypeAliasSpecification(p, exp)
    | CustomTypeDefinition(p, accessControlledCtors) ->
        match accessControlledCtors |> withPublicAccess with
        | Just ctors -> CustomTypeSpecification(p, ctors)
        | Nothing -> OpaqueTypeSpecification p

let definitionToSpecificationWithPrivate (def: Definition<'A>) : Specification<'A> =
    match def with
    | TypeAliasDefinition(p, exp) -> TypeAliasSpecification(p, exp)
    | CustomTypeDefinition(p, accessControlledCtors) ->
        accessControlledCtors |> withPrivateAccess |> customTypeSpecification p

let variable attributes name = Variable(attributes, name)


let extensibleRecord attributes variableName fieldTypes =
    ExtensibleRecord(attributes, variableName, fieldTypes)

let ``function`` attributes argumentType returnType =
    Function(attributes, argumentType, returnType)

let inline func attributes argumentType returnType =
    Function(attributes, argumentType, returnType)

let unit attributes = Unit(attributes)

let field name fieldType = { Name = name; Type = fieldType }

let mapFieldName f (field: Field<'A>) = field.MapName f

let mapFieldType f (field: Field<'A>) : Field<'B> = field.MapType f

let matchField (matchFieldName: Pattern<Name, 'A>) (matchFieldType: Pattern<Type<'A>, 'B>) field =
    Maybe.map2 Tuple.pair (matchFieldName field.Name) (matchFieldType field.Type)

let rec mapTypeAttributes (f: 'a -> 'b) : Type<'a> -> Type<'b> =
    function
    | Variable(a, name) -> Variable(f (a), name)
    | Reference(a, fQName, argTypes) ->
        let newArgTypes = argTypes |> List.map (mapTypeAttributes f)

        Reference(f (a), fQName, newArgTypes)

    | Tuple(a, elemTypes) -> Tuple((f a), (elemTypes |> List.map (mapTypeAttributes f)))

    | Record(a, fields) -> Record((f a), (fields |> List.map (mapFieldType (mapTypeAttributes f))))

    | ExtensibleRecord(a, name, fields) ->
        ExtensibleRecord((f a), name, (fields |> List.map (mapFieldType (mapTypeAttributes f))))

    | Function(a, argType, returnType) ->
        Function((f a), (argType |> mapTypeAttributes f), (returnType |> mapTypeAttributes f))
    | Unit a -> Unit(f a)

let typeAttributes (typeExpr: Type<'Attributes>) : 'Attributes = typeExpr.Attributes

let eraseAttributes: Definition<'a> -> Definition<unit> =
    function
    | TypeAliasDefinition(typeVars, tpe) -> TypeAliasDefinition(typeVars, mapTypeAttributes (fun _ -> ()) tpe)
    | CustomTypeDefinition(typeVars, acsCtrlConstructors) ->
        let eraseCtor (types: ('Name * Type<'a>) list) : ('Name * Type<unit>) list =
            types |> List.map (fun (n, t) -> (n, mapTypeAttributes (fun _ -> ()) t))

        let eraseAccessControlledCtors acsCtrlCtors =
            AccessControlled.map (fun ctors -> ctors |> Dict.map (fun _ -> eraseCtor)) acsCtrlCtors

        CustomTypeDefinition(typeVars, eraseAccessControlledCtors acsCtrlConstructors)

type Definition<'A> with

    member this.EraseAttributes() = eraseAttributes this

type Type =
    static member Reference(name: FQName) : Type<unit> = Reference((), name, [])

    static member Reference(attributes: 'A, name: FQName, [<ParamArray>] typeParameters: Type<'A> array) =
        Reference(attributes, name, typeParameters |> List.ofArray)

module Constructors =
    let empty<'a> : Constructors<'a> = Constructors.Empty()
