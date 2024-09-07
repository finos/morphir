package org.finos.morphir.trees

trait Container[+T] extends Element {
  def content: T
}

trait ElementContainerBase[+E <: Element, +Col[+_]] extends Container[Col[E]] with ElementTraversal
trait ElementContainer[+E <: Element]               extends ElementContainerBase[E, Seq]

trait IndexedElementContainer[+E <: Element] extends ElementContainerBase[E, IndexedSeq] {
  inline def apply(index: Int): E = content(index)
}

trait Module extends ElementContainer[ModuleMember]

trait Session extends ElementContainer[TopLevelElement]
