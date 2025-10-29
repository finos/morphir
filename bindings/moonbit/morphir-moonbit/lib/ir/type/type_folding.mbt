
// ///|
// pub fn[Attribs, Z] fold(
//   self : Type[Attribs],
// ) -> Z raise? {
//   loop(self, @list.empty()) {
//     (Variable(attribs, name), _) => {
//       break on_variable(attribs, name)
//     }
//     (Unit(attribs), _) => {
//       break on_unit(attribs)
//     }
//     (Tuple(attribs, element_types), More(head, tail=tail)) => {
//       ...
//     }
//     _ => ...
    
//   }
// }