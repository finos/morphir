package org.finos.morphir.modeling

// abstract class Concept extends Product with Serializable {
//   type Self

// }

abstract class Element extends Product with Serializable {
  type Self <: Element
  type Attribs <: Attributes
  def attributes: Attribs
}

trait Member extends Element {
  type Self <: Member
}

trait ModuleMember extends Member {
  type Self <: ModuleMember
}

trait Declaration extends Member {
  type Self <: Declaration
}

trait TypeMember extends Member {
  type Self <: TypeMember
}

trait TypeDeclaration extends Declaration with TypeMember {
  type Self <: TypeDeclaration
}
