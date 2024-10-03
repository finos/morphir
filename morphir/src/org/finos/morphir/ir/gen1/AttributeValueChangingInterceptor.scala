package org.finos.morphir.ir.gen1

sealed trait AttributeValueChangingInterceptor[A] extends ((A, A) => A)
object AttributeValueChangingInterceptor {

  def apply[A](f: (A, A) => A): AttributeValueChangingInterceptor[A] = new AttributeValueChangingInterceptor[A] {
    override def apply(v1: A, v2: A): A = f(v1, v2)
  }

  def KeepNewValue[A]: AttributeValueChangingInterceptor[A] =
    AttributeValueChangingInterceptor((_, newValue) => newValue)

  def KeepOldValue[A]: AttributeValueChangingInterceptor[A] =
    AttributeValueChangingInterceptor((oldValue, _) => oldValue)
}
