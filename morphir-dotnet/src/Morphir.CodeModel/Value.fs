namespace Morphir.CodeModel

[<Struct>]
type FieldLabel = FieldLabel of Text:string

[<Struct>]
type ScalarName = ScalarName of Text:string

[<Struct>]
type VariantName = VariantName of Text:string

type Value =
    | Bool of bool
    | String of string
    | Uint8 of uint8
    | Uint16 of uint16
    | Uint32 of uint32
    | Uint64 of uint64
    | Int8 of int8
    | Int16 of int16
    | Int32 of int32
    | Int64 of int64   
    | Optional of Value option
    | List of Value list
    | Record of Map<FieldLabel, Value>
    | Tuple of Value list
    | Variant of VariantName * Value option
    | AnnotatedValue of Value * ValueAnnotations
    
    static let (|Unit|_|) = function
        | Tuple [] -> Some ()
        | _ -> None
        
    static member Unit: Value = Tuple []
and ValueAnnotation =
    | TypeAnnotation of Type : Morphir.CodeModel.Type
    | ScalarAnnotation of ScalarName
and ValueAnnotations =
    | Single of ValueAnnotation
    | Many of ValueAnnotation * ValueAnnotations