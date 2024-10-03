package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.Attribute.Binding

final class Attributes private (private val map: Map[Attribute[Any], AnyRef]) {
  self =>
  def ++=(bindings: Seq[Binding[_]]): Attributes = new Attributes(
    (self.map.toVector ++ bindings.map(b => b.property.asInstanceOf[Attribute[Any]] -> b.value.asInstanceOf[AnyRef]))
      .foldLeft[Map[Attribute[Any], AnyRef]](Map()) { case (acc, (property, value)) =>
        acc.updated(
          property,
          acc.get(property).fold(value)(property.valueCangeInterceptor(_, value).asInstanceOf[AnyRef])
        )
      }
  )
  def get[V](property: Attribute[V]): V =
    map.get(property.asInstanceOf[Attribute[Any]]).fold(property.initial)(_.asInstanceOf[V])

  def hasProperty[V](property: Attribute[V]): Boolean = map.contains(property.asInstanceOf[Attribute[Any]])

  private def overwrite[V](property: Attribute[V], value: V): Attributes =
    new Attributes(map.updated(property.asInstanceOf[Attribute[Any]], value.asInstanceOf[AnyRef]))

  def update[V](property: Attribute[V], f: V => V): Attributes =
    overwrite(property, f(get(property)))

  def set[V](property: Attribute[V], value: V): Attributes =
    update[V](property, property.valueCangeInterceptor(_, value))
}

object Attributes {
  type Id[A]
  val empty: Attributes = new Attributes(Map.empty)
  def apply(bindings: Binding[_]*): Attributes =
    empty ++= bindings
}
