package org.finos.morphir.trees

trait Attributes:
  type Self <: Attributes
object Attributes:
  val default: Attributes = new Attributes {}
