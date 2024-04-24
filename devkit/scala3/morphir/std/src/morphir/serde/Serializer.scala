package morphir.serde

import morphir.std.result.Result

trait Serializer {
  type Ok
  type Error

  def serializeBoolean(value: Boolean): Result[Error, Ok]
  def serializeByte(value: Byte): Result[Error, Ok]
  def serializeShort(value: Short): Result[Error, Ok]
  def serializeInt(value: Int): Result[Error, Ok]
  def serializeLong(value: Long): Result[Error, Ok]
  def serializeFloat(value: Float): Result[Error, Ok]
  def serializeDouble(value: Double): Result[Error, Ok]
  def serializeChar(value: Char): Result[Error, Ok]
  def serializeString(value: String): Result[Error, Ok]
  def serializeNone(): Result[Error, Ok]
  def serializeSome[A: Serialize](value: A): Result[Error, Ok]
  def serializeUnit(): Result[Error, Ok]
  def serializeUnitStruct(name: String): Result[Error, Ok]
}

object Serializer:
  type Aux[TOk, TError] = Serializer { type Ok = TOk; type Error = TError }
  trait Generic[TOk, TError] extends Serializer:
    type Ok = TOk
    type Error = TError
