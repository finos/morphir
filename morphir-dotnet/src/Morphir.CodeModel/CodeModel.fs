namespace Morphir.CodeModel
open System 
open System.Reflection.Metadata
open Morphir.IR

[<RequireQualifiedAccess>]
module LabelTag =
    type LocalName =
        interface
        end

    type TypeVariable =
        interface
        end

    type Variable =
        interface
        end

    type Variant =
        interface
        end

    type Field =
        interface
        end

    type Scalar =
        interface
        end

type FieldName = Label<LabelTag.Field>
type LocalName = Label<LabelTag.LocalName>
type TypeVariableName = Label<LabelTag.TypeVariable>
type VariableName = Label<LabelTag.Variable>
type VariantName = Label<LabelTag.Variant>
type ScalarName = Label<LabelTag.Scalar>

type Ref =
    | ModuleLocalRef of LocalName
    | PackageLocalRef of QName
    | GlobalRef of FQName

type Annotation =
    interface
    end

and ContainsAnnotations =
    abstract member Annotations: Annotation list
//TODO: Add functionality for pulling out type level and value level annotations

and ThreePartVersion =
    { Major: int; Minor: int; Patch: int }

and CommonAnnotation =
    | Exported of ExportedFlag
    | ThreePartVersionNumber of ThreePartVersion
    interface Annotation

and TypeLevelAnnotations =
    | Single of TypeLevelAnnotation
    | Many of Head: TypeLevelAnnotation * Tail: TypeLevelAnnotation list

    member this.All =
        match this with
        | Single a -> [ a ]
        | Many(h, t) -> h :: t

and TypeLevelAnnotation =
    | Common of CommonAnnotation

    interface Annotation

and ValueLevelAnnotation =
    | Common of CommonAnnotation
    | TypeAnnotation of Type: Type
    | ScalarAnnotation of ScalarName

    interface Annotation

and ValueLevelAnnotations =
    | Single of ValueLevelAnnotation
    | Many of Head: ValueLevelAnnotation * Tail: ValueLevelAnnotation list

    static member Create(annotation: ValueLevelAnnotation, [<ParamArray>]others: ValueLevelAnnotation array) =
        match others with
        | [||] -> Single annotation
        | _ -> Many(annotation, others |> List.ofArray)
    member this.All =
        match this with
        | Single a -> [ a ]
        | Many(h, t) -> h :: t

and Type =
    | Annotated of Underlying:Type * TypeLevelAnnotations
    | ExtensibleRecord of Name:VariableName * Fields:Field list
    | Function of From:Type * To:Type
    | Record of Fields:Field list
    | Reference of Ref * Type list
    | Tuple of Type list
    | Variable of Name: TypeVariableName

    static let (|Unit|_|) =
        function
        | Tuple [] -> Some()
        | _ -> None
    
    [<TailCall>]
    static let rec allAnnotations(type_: Type) =
        let rec loop type_ acc =
            match type_ with
            | Annotated(underlying, ann) -> loop underlying (acc @ ann.All)
            | _ -> acc
        loop type_ []
        
    member this.AllAnnotations = allAnnotations this        
    static member Unit: Type = Tuple []
    
and TypeDefinition =
    | TypeAliasDefinition of TypeVars: TypeVariableName list * TypeExpr: Type
    | OpaqueTypeDefinition of TypeVars: TypeVariableName list * Extends: Exportable<Type> option
    | VariantTypeDefinition of TypeVars: TypeVariableName list * Constructors: Exportable<TypeConstructors> //TODO: Consider if export should only exist at the module level in this form, and bubble down through annotations
    | DerivedTypeDefinition of TypeVars: TypeVariableName list * Details: DerivedTypeDefinitionDetails
    | AnnotatedTypeDefinition of Underlying:TypeDefinition * TypeLevelAnnotations
    
    [<TailCall>]
    static let rec typeVars = function
        | TypeAliasDefinition(vars, _) -> vars
        | OpaqueTypeDefinition(vars, _) -> vars
        | VariantTypeDefinition(vars, _) -> vars
        | DerivedTypeDefinition(vars, _) -> vars
        | AnnotatedTypeDefinition(underlying, _) -> typeVars underlying
        
    [<TailCall>]
    static let rec allAnnotations(typeDef: TypeDefinition) =
        let rec loop typeDef acc = 
            match typeDef with
            | AnnotatedTypeDefinition(underlying, ann) -> loop underlying (acc @ ann.All)
            | TypeAliasDefinition(_, type_) -> acc @ type_.AllAnnotations
            | OpaqueTypeDefinition(_, Some type_) -> acc @ type_.Underlying.AllAnnotations            
            | _ -> acc
        loop typeDef []
        
    member this.AllAnnotations = allAnnotations this
    member this.TypeVars = typeVars this
        
and TypeSpecification =
    | TypeAliasSpecification of TypeVars: TypeVariableName list * TypeExpr: Type
    | OpaqueTypeSpecification of TypeVars: TypeVariableName list
    | VariantTypeSpecification of TypeVars: TypeVariableName list * Constructors: TypeConstructors
    | DerivedTypeSpecification of TypeVars: TypeVariableName list * Details: DerivedTypeSpecificationDetails     
        
    static member TypeAlias(typeExpr: Type) : TypeSpecification = TypeAliasSpecification([], typeExpr)
    member this.IsGeneric =
        match this with
        | TypeAliasSpecification(vars, _) -> vars.Length > 0
        | OpaqueTypeSpecification(vars) -> vars.Length > 0
        | VariantTypeSpecification(vars, _) -> vars.Length > 0
        | DerivedTypeSpecification(vars, _) -> vars.Length > 0
        
and DerivedTypeDefinitionDetails = {BaseType: Type; FromBaseType: Ref; ToBaseType: Ref}        
and DerivedTypeSpecificationDetails = { BaseType: Type; FromBaseType: Ref; ToBaseType: Ref }
and Field = {fieldName:FieldName; Type:Type}
and TypeConstructors = TypeConstructors of Map<VariantName, TypeConstructorArgs>
and TypeConstructor = TypeConstructor of VariantName * TypeConstructorArgs
and TypeConstructorArgs = TypeConstructorArgs of (Name * Type) list
and TypeDetails =
    | Type of Type
    | TypeConstructor of TypeConstructor
    | TypeSpecification of TypeSpecification
    | TypeDefinition of TypeDefinition
and PrimitiveValue =
    | Bool of bool
    | Char of char
    | String of string
    | Uint8 of uint8
    | Uint16 of uint16
    | Uint32 of uint32
    | Uint64 of uint64
    | Int8 of int8
    | Int16 of int16
    | Int32 of int32
    | Int64 of int64

and Value =
    | Primitive of PrimitiveValue
    | Optional of Value option
    | List of Value list
    | Record of Map<FieldName, Value>
    | Tuple of Value list
    | Variant of VariantName * Value option
    | AnnotatedValue of Value * ValueLevelAnnotations

    //static member Scalar(primitive: PrimitiveValue) : Value = AnnotatedValue(Primitiveprimitive, )
    static let (|Unit|_|) =
        function
        | Tuple [] -> Some()
        | _ -> None

    static member Int8(input: int8) : Value = Primitive(Int8 input)
    static member Unit: Value = Tuple []

and Expr =
    | Apply of Expr * Expr * Annotations: Annotation list
    | Constant of Value: PrimitiveValue * Annotations: Annotation list
    | IfThenElse of Expr * Expr * Expr * Annotations: Annotation list
    | Reference of Ref * Annotations: Annotation list
    | Tuple of Expr list * Annotations: Annotation list
    | Variable of VariableName * Annotations: Annotation list

    static ifThenElse (condition: Expr) (thenBranch: Expr) (elseBranch: Expr) : Expr =
        IfThenElse(condition, thenBranch, elseBranch, [])

    static let variable (name: VariableName) : Expr = Variable(name, [])
    static let unit: Expr = Tuple([], [])
    static member Unit: Expr = Tuple([], [])
and Ast =
    | Module of ModuleName 
    | Package of PackageName * Modules: Map<ModuleName, Exportable<Module>>
and Module = { Types: TypeSpecification list}
and ExportedFlag =   
    | NotExported = 0
    | Exported = 1
and Exportable<'T> =
    | Exported of Underlying:'T
    | NotExported of Underlying:'T    
    member this.Underlying:'T =
        match this with
        | Exported value -> value
        | NotExported value -> value
        
    member inline this.Flag =
        match this with
        | Exported _ -> ExportedFlag.Exported
        | NotExported _ -> ExportedFlag.NotExported

and IntrinsicType =
    static let unit = Type.Tuple []

module Exportable =
    let (|Underlying|)(exportable: Exportable<'T>):'T =
        match exportable with
        | Exported value -> value
        | NotExported value -> value
        
    let isExported = function | Exported _ -> true | NotExported _ -> false