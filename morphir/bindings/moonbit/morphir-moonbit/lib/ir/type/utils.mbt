pub fn[Attribs] Type::iter(self: Type[Attribs]) -> Iter[Type[Attribs]] {
  Iter::new(yield_ => {
    loop(@list.singleton(self)) {
      (Empty) => break IterEnd
      (More(Unit(_) as t, tail=rest)) => {
        guard yield_(t) is IterContinue else {break IterEnd}
        continue(rest)
      }
      (More(Variable(_, _) as t, tail=rest)) => {
        guard yield_(t) is IterContinue else {break IterEnd}
        continue(rest)
      }      
      (More(Reference(_, _, type_args) as t, tail=rest)) => {
        guard yield_(t) is IterContinue else {break IterEnd}
        continue(type_args.concat(rest))
      }
      (More(Tuple(_, element_types) as t, tail=rest)) => {
        guard yield_(t) is IterContinue else {break IterEnd}
        continue(element_types.concat(rest))
      }
      (More(Record(_, fields) as t, tail=rest)) => {
        guard yield_(t) is IterContinue else {break IterEnd}
        let field_types = fields.map((f) => f.tpe)
        continue(field_types.concat(rest))
      }
      (More(ExtensibleRecord(_, _, fields) as t, tail=rest)) => {
        guard yield_(t) is IterContinue else {break IterEnd}
        let field_types = fields.map((f) => f.tpe)
        continue(field_types.concat(rest))
      }
      (More(Function(_, param_type, return_type) as t, tail=rest)) => {
        guard yield_(t) is IterContinue else {break IterEnd}
        continue(@list.cons(param_type, @list.cons(return_type, rest)))
      } 
    } 
  })
}