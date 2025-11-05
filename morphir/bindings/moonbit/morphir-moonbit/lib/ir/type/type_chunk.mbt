
pub enum TypeChunk[A] {
  VariableStart(A, Name)
  VariableEnd(A)

  ReferenceStart(A, @fqname.FQName)
  ReferenceEnd(A)

  TupleStart(A)
  TupleEnd(A)

  RecordStart(A)
  RecordEnd(A)

  ExtensibleRecordStart(A, Name)
  ExtensibleRecordEnd(A)

  FunctionStart(A)
  FunctionParamType(A, Type[A])
  FunctionReturnType(A, Type[A])
  FunctionEnd(A)  


  UnitStart(A)
  UnitEnd(A)

  SequenceStart(A, Length)
  SequenceItem(A, Index, Type[A])
  SequenceEnd(A, Length)
  
  Field(A, Name, Type[A])
  
} derive(Eq, Hash, Show)

pub struct Length(Int64) derive(Eq, Hash, Show)
pub struct Index(Int64) derive(Eq, Hash, Show)