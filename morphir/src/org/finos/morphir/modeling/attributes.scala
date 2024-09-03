package org.finos.morphir.modeling

trait Attributes:
  type Self <: Attributes
object Attributes:
  val default: Attributes = new Attributes {}
