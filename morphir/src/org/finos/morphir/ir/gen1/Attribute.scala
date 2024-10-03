package org.finos.morphir.ir.gen1

import izumi.reflect.Tag

sealed class Attribute[A](
  val name: String,
  val initial: A,
  val valueCangeInterceptor: AttributeValueChangingInterceptor[A],
  private val tag: Tag[A]
) extends Serializable { self =>
  import Attribute.*
  def :=(value: A): Binding[A] = Binding(self, value)
  override def equals(that: Any): Boolean = (that: @unchecked) match {
    case that: Attribute[_] => (name, tag) == ((that.name, that.tag))
  }

  override lazy val hashCode: Int =
    (name + tag).hashCode
}
object Attribute {

  def apply[A](name: String, initial: A)(implicit tag: Tag[A]): Attribute[A] =
    new Attribute(name, initial, AttributeValueChangingInterceptor.KeepNewValue, tag)

  def apply[A](name: String, initial: A, interceptor: AttributeValueChangingInterceptor[A])(implicit
    tag: Tag[A]
  ): Attribute[A] =
    new Attribute(name, initial, interceptor, tag)

  /** Alias for `makeMonoidal`.
    */
  def makeMetric[V](name: String, initial: V, combine: (V, V) => V)(implicit tag: Tag[V]): Attribute[V] =
    makeMonoidal(name, initial, combine)

  def makeMonoidal[V](name: String, initial: V, combine: (V, V) => V)(implicit tag: Tag[V]): Attribute[V] =
    new Attribute[V](name, initial, AttributeValueChangingInterceptor(combine), tag)

  def unapply[V](property: Attribute[V]): Some[(String, V, AttributeValueChangingInterceptor[V])] = Some(
    (property.name, property.initial, property.valueCangeInterceptor)
  )

  final case class Binding[V](property: Attribute[V], value: V)
}

sealed abstract case class AttributeValue[V] private (value: V, tag: Tag[V])
object AttributeValue {
  def apply[V](value: V)(implicit tag: Tag[V]): AttributeValue[V] = new AttributeValue(value, tag) {}
}
