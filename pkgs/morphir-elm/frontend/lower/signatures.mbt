///|
/// The argument and the result of a function type, looking through parentheses
/// (a `Tupled` with one item). `None` for any other annotation.
fn function_parts(
  annotation : @ast.Node[@ast.TypeAnnotation],
) -> (@ast.Node[@ast.TypeAnnotation], @ast.Node[@ast.TypeAnnotation])? {
  let mut t = annotation
  while t.value is Tupled(items) && items.length() == 1 {
    t = items[0]
  }
  match t.value {
    FunctionTypeAnnotation(arg, result) => Some((arg, result))
    _ => None
  }
}

///|
/// The placeholder type `t-n`, marked unknown, of an unannotated value or let
/// definition.
fn placeholder(n : Int32) -> @ir.Type {
  let name = @ir.Name::parse("t-" + n.to_string()) catch { _ => panic() }
  Variable(@ir.TypeAttributes::default().with_unknown(), name)
}
