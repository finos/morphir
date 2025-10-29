

///|
pub fn[A] Type::to_string(self : Type[A]) -> String {
  enum Frame {
    Node(Type[A])
    Emit(String)
    FieldEmit(Name, Type[A])
    Close(String)
  }

  let sb = StringBuilder::new()

  loop(@list.singleton(Node(self))) {
    Empty => break sb.to_string()
    More(Emit(str) | Close(str), tail=rest) => {
      sb.write_string(str)
      continue(rest)
    }
    More(Node(Variable(_, name)), tail=rest) => {
      sb.write_string(name.to_camel_case())
      continue(rest)
    }
    More(Node(Unit(_)), tail=rest) => {
        sb.write_string("()")
        continue(rest)
    }
    More(FieldEmit(field_name, field_type), tail=rest) => {
      sb.write_string(field_name.to_camel_case() + ": ")
      continue(@list.cons(Node(field_type), rest))
    }
    More(Node(Reference(_, {package_name, module_path, local_name}, params)), tail=rest) => {
      let ref_name = package_name.to_string(Name::to_title_case, ".") + "." +
        module_path.to_string(Name::to_title_case, ".") + "." +
        local_name.to_title_case()

      sb.write_string(ref_name)
      if params.is_empty() {
        continue(rest)
      } else {
        sb.write_string(" ")
        let param_ops = params.map((param) => Node(param)).intersperse(Emit(" "))
        continue(param_ops.concat(rest))
      }
    }
    More(Node(Function(_, param_type, return_type)), tail=rest) => {
      let ops = @list.cons(Node(param_type), @list.cons(Emit(" -> "), @list.singleton(Node(return_type))))
      continue(ops.concat(rest))
    }
    More(Node(Tuple(_, elements)), tail=rest) => {
      sb.write_string("( ")
      let stack = @list.cons(Close(" )"), rest)
      let ops = elements.map((elem) => Node(elem)).intersperse(Emit(", "))
      continue(ops.concat(stack))
    }
    More(Node(Record(_, fields)), tail=rest) => {
      sb.write_string("{ ")
      let stack = @list.cons(Close(" }"), rest)
      let field_ops = fields.map((field) => FieldEmit(field.name, field.tpe)).intersperse(Emit(", "))
      continue(field_ops.concat(stack))
    }
    More(Node(ExtensibleRecord(_, var_name, fields)), tail=rest) => {
      sb.write_string("{ ")
      sb.write_string(var_name.to_camel_case() + " | ")
      let stack = @list.cons(Close(" }"), rest)
      let field_ops = fields.map((field) => FieldEmit(field.name, field.tpe)).intersperse(Emit(", "))
      continue(field_ops.concat(stack))
    }
  }  
}
