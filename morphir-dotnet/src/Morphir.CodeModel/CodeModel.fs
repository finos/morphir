namespace Morphir.CodeModel

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
    
and CommonAnnotation =    
    | Exported
    interface Annotation

and TypeLevelAnnotations =
    | Single of TypeLevelAnnotation
    | Many of Head:TypeLevelAnnotation * Tail:TypeLevelAnnotation list
    member this.All = 
        match this with
        | Single a -> [a]
        | Many (h, t) -> h :: t
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
    | Many of Head:ValueLevelAnnotation * Tail:ValueLevelAnnotation list
    member this.All = 
        match this with
        | Single a -> [a]
        | Many (h, t) -> h :: t
and Type =
    | Reference of Ref * Type list
    | Tuple of Type list
    | Variable of TypeVariableName
    | Annotated of Type * TypeLevelAnnotations

    static let (|Unit|_|) =
        function
        | Tuple [] -> Some()
        | _ -> None

    static member Unit: Type = Tuple []
and TypeSpecification =
    | TypeAliasSpecification of TypeVars : TypeVariableName list * TypeExpr:Type
    | ScalarTypeSpecification of TypeVars: TypeVariableName list * Extends:Type option
    | VariantTypeSpecification of TypeVars: TypeVariableName list
and TypeConstructorArgs =
    | TypeConstructorArgs of Type list

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

    static let (|Unit|_|) =
        function
        | Tuple [] -> Some()
        | _ -> None

    static member Int8(input:int8): Value = Primitive (Int8 input)
    static member Unit: Value = Tuple []

and Expr =
    | Apply of Expr * Expr * Annotations:Annotation list
    | Constant of Value: PrimitiveValue * Annotations:Annotation list
    | IfThenElse of Expr * Expr * Expr * Annotations:Annotation list
    | Reference of Ref * Annotations:Annotation list
    | Tuple of Expr list * Annotations:Annotation list
    | Variable of VariableName * Annotations:Annotation list   
    
    static ifThenElse (condition:Expr) (thenBranch:Expr) (elseBranch:Expr): Expr = IfThenElse (condition, thenBranch, elseBranch, [])
    static let variable(name:VariableName): Expr = Variable(name, [])
    static let unit: Expr = Tuple([], [])
    static member Unit: Expr = Tuple ([], [])


and IntrinsicType =
    static let unit = Type.Tuple []