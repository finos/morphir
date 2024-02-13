namespace Morphir.CodeModel.IR



type BoolContext = BoolContext of value : bool

type IRVisitor =
  abstract member Bool: ctx: BoolContext -> unit
  
type IRNode = interface end  

// type ToValue<'T> =
//   static abstract member ConvertToValue : input:'T -> Value
  
and StandardData =
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
  | Unit
  // interface ToValue<StandardData> with
  //   static member ConvertToValue(input:StandardData) = Data (Basic input)

and Data =
  | Basic of StandardData
  | Optional of Data option
  interface IRNode
  

and Value =
  | Data of Data
  | List of Value list
  | Record of (string * Value) list
  | Variant of string * Value option
  


  
[<RequireQualifiedAccess>]  
module Value =
  
  let (|Bool|_|) (data:Data) = 
    match data with
    | Basic (Bool x) -> Some x
    | _ -> None
  
  let (|String|_|) (data:Data) =
    match data with
    | Basic (String x) -> Some x
    | _ -> None
  
  let bool (x: bool) = Data (Basic (Bool x))                                    
  let int8 (x: int8) = Data (Basic (Int8 x))
  let int16 (x: int16) = Data (Basic (Int16 x))
  let int32 (x: int32) = Data (Basic (Int32 x))
  let int64 (x: int64) = Data (Basic (Int64 x))
  let uint8 (x: uint8) = Data (Basic (Uint8 x))
  let uint16 (x: uint16) = Data (Basic (Uint16 x))
  let uint32 (x: uint32) = Data (Basic (Uint32 x))
  let uint64 (x: uint64) = Data (Basic (Uint64 x))
  let string (str: string) = Data (Basic (String str))
  let unit = Data (Basic Unit)
  
  let fromStandardData (data:StandardData) = Data (Basic data)
  let fromData (data:Data) = Data data  