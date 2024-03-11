module Morphir.IR.Module

open Morphir.IR.Documented
open Morphir.IR.Name
open Morphir.IR.Path
open Morphir.IR.AccessControlled
open Morphir.IR.Value
open Morphir.SDK.Dict
open Morphir.SDK.Maybe
open Morphir.SDK

/// A module name is a unique identifier for a module within a package. It is represented by a path,
/// which is a list of names.
type ModuleName = Path

/// A qualified module name is a globally unique identifier for a module. It is represented by a tuple
/// of the package and the module name.
type QualifiedModuleName = Path * Path

type Specification<'TA> = {
    Types: Dict<Name, Documented<Type.Specification<'TA>>>
    Values: Dict<Name, Documented<Value.Specification<'TA>>>
    Doc: Maybe<string>
}

type Definition<'TA, 'VA> = {
    Types: Dict<Name, AccessControlled<Documented<Type.Definition<'TA>>>>
    Values: Dict<Name, AccessControlled<Documented<Value.Definition<'TA, 'VA>>>>
    Doc: Maybe<string>
}

let emptySpecification: Specification<'TA> = {
    Types = Dict.empty
    Values = Dict.empty
    Doc = Nothing
}

let emptyDefinition: Definition<'TA, 'VA> = {
    Types = Dict.empty
    Values = Dict.empty
    Doc = Nothing
}

let specification
    (types: Dict<Name, Documented<Type.Specification<'TA>>>)
    (values: Dict<Name, Documented<Value.Specification<'TA>>>)
    (doc: Maybe<string>)
    : Specification<'TA> =
    {
        Types = types
        Values = values
        Doc = doc
    }

let definition
    (types: Dict<Name, AccessControlled<Documented<Type.Definition<'TA>>>>)
    (values: Dict<Name, AccessControlled<Documented<Value.Definition<'TA, 'VA>>>>)
    (doc: Maybe<string>)
    : Definition<'TA, 'VA> =
    {
        Types = types
        Values = values
        Doc = doc
    }

let lookupTypeSpecification
    (localName: Name)
    (moduleSpec: Specification<'ta>)
    : Maybe<Type.Specification<'ta>> =
    moduleSpec.Types
    |> Dict.get localName
    |> Maybe.map Documented.value

let lookupValueSpecification
    (localName: Name)
    (moduleSpec: Specification<'ta>)
    : Maybe<Value.Specification<'ta>> =
    moduleSpec.Values
    |> Dict.get localName
    |> Maybe.map Documented.value

/// Look up a value definition by its name in a module specification.
let lookupValueDefinition
    localName
    (moduleDef: Definition<'ta, 'va>)
    : Maybe<Value.Definition<'ta, 'va>> =
    moduleDef.Values
    |> Dict.get localName
    |> Maybe.map (
        withPrivateAccess
        >> Documented.value
    )

let definitionToSpecification (def: Definition<'TA, 'VA>) : Specification<'TA> = {
    Types =
        def.Types
        |> Dict.toList
        |> List.filterMap (fun (path, accessControlledType) ->
            accessControlledType
            |> withPublicAccess
            |> Maybe.map (fun typeDef ->
                (path,
                 typeDef
                 |> Documented.map Type.definitionToSpecification)
            )
        )
        |> Dict.fromList
    Values =
        def.Values
        |> Dict.toList
        |> List.filterMap (fun (path, accessControlledValue) ->
            accessControlledValue
            |> withPublicAccess
            |> Maybe.map (fun valueDef ->
                (path,
                 valueDef
                 |> Documented.map Value.definitionToSpecification)
            )
        )
        |> Dict.fromList
    Doc = def.Doc
}

let definitionToSpecificationWithPrivate (def: Definition<'ta, 'va>) : Specification<'ta> =
    let types =
        def.Types
        |> Dict.toList
        |> Morphir.SDK.List.map (fun (path, accessControlledType) ->
            (path,
             accessControlledType
             |> withPrivateAccess
             |> Documented.map Type.definitionToSpecificationWithPrivate)
        )
        |> Dict.fromList

    let values =
        def.Values
        |> Dict.toList
        |> Morphir.SDK.List.map (fun (path, accessControlledValue) ->
            (path,
             accessControlledValue
             |> withPrivateAccess
             |> Documented.map Value.definitionToSpecification)
        )
        |> Dict.fromList

    {
        Types = types
        Values = values
        Doc = def.Doc
    }

// /// Find all the modules that this module depends on.
// let dependsOnModules (moduleDef:Definition<'ta,'va>): Set<QualifiedModuleName> =
//     collectReferences moduleDef
//         |> Set.map (fun ( packageName, moduleName, _ ) -> ( packageName, moduleName )

module Specification =
    let empty = {
        Types = Map.empty
        Values = Map.empty
        Doc = Nothing
    }

type Definition<'TA, 'VA> with

    member this.ToSpecification() : Specification<'TA> = definitionToSpecification this
