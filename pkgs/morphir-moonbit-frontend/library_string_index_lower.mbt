///|
fn LibraryLowerer::string_length(
  self : LibraryLowerer,
  value : @ir.Value,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let text = LibraryTypeUse::{
    scalar: Text,
    spelling: "String",
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let int32 = LibraryTypeUse::{
    scalar: SignedInt32,
    spelling: "Int32",
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  self.invoke(
    "morphir/moonbit-source:string#length-int32",
    [(value, text), (self.bound(source), library_integer_type())],
    int32,
    source,
    "utf16-code-unit-length",
    metadata_key="moonbit-source-string-index-v1",
    runtime_extension="morphir-moonbit-source-string-index-v1",
  )
}

///|
fn LibraryLowerer::string_slice(
  self : LibraryLowerer,
  value : @ir.Value,
  start : @ir.Value,
  end : @ir.Value,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let text = LibraryTypeUse::{
    scalar: Text,
    spelling: "String",
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let int32 = LibraryTypeUse::{
    scalar: SignedInt32,
    spelling: "Int32",
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let receiver_name = self.fresh(value, "slice-receiver", source)
  let start_name = self.fresh(start, "slice-start", source)
  let end_name = self.fresh(end, "slice-end", source)
  let result = self.invoke(
    "morphir/moonbit-source:string#slice-owned",
    [
      (
        @ir.Value::Variable(library_attributes(source, text), receiver_name),
        text,
      ),
      (
        @ir.Value::Variable(library_attributes(source, int32), start_name),
        int32,
      ),
      (@ir.Value::Variable(library_attributes(source, int32), end_name), int32),
      (self.bound(source), library_integer_type()),
    ],
    text,
    source,
    "surrogate-aware-slice",
    metadata_key="moonbit-source-string-index-v1",
    runtime_extension="morphir-moonbit-source-string-index-v1",
  )
  @ir.Value::LetDefinition(
    library_attributes(source, text),
    receiver_name,
    @ir.ValueDefinition::ExpressionBody([], text, value),
    @ir.Value::LetDefinition(
      library_attributes(source, text),
      start_name,
      @ir.ValueDefinition::ExpressionBody([], int32, start),
      @ir.Value::LetDefinition(
        library_attributes(source, text),
        end_name,
        @ir.ValueDefinition::ExpressionBody([], int32, end),
        result,
      ),
    ),
  )
}
