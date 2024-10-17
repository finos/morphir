package morphir.serde

trait Serializer[-Type, FormatType]:
  self =>
  def serialize(value: Type): FormatType
  final def contramap[U](f: U => Type): Serializer[U, FormatType] = new Serializer[U, FormatType]:
    def serialize(value: U): FormatType = self.serialize(f(value))

  final def mapSerialize[NewFormatType](f: FormatType => NewFormatType): Serializer[Type, NewFormatType] =
    new Serializer[Type, NewFormatType]:
      def serialize(value: Type): NewFormatType = f(self.serialize(value))
end Serializer

object Serializer:
  def apply[Type, FormatType](using serializerInstance: Serializer[Type, FormatType]): Serializer[Type, FormatType] =
    serializerInstance
end Serializer

trait Deserializer[+Type, FormatType]:
  self =>
  def deserialize(input: FormatType): Either[Throwable, Type]

  final def map[U](f: Type => U): Deserializer[U, FormatType] = new Deserializer[U, FormatType]:
    def deserialize(input: FormatType): Either[Throwable, U] = self.deserialize(input).map(f)

  final def flatMap[U](f: Type => Either[Throwable, U]): Deserializer[U, FormatType] = new Deserializer[U, FormatType]:
    def deserialize(input: FormatType): Either[Throwable, U] = self.deserialize(input).flatMap(f)

  final def mapDeserialize[U](f: U => FormatType): Deserializer[Type, U] = new Deserializer[Type, U]:
    def deserialize(input: U): Either[Throwable, Type] = self.deserialize(f(input))

  final def flatMapDeserialize[U](f: U => Either[Throwable, FormatType]): Deserializer[Type, U] =
    new Deserializer[Type, U]:
      def deserialize(input: U): Either[Throwable, Type] = f(input).flatMap(self.deserialize)
end Deserializer

object Deserializer:
  def apply[Type, FormatType](using
    deserializerInstance: Deserializer[Type, FormatType]
  ): Deserializer[Type, FormatType] = deserializerInstance
end Deserializer

type Serde[Type, FormatType] = Serializer[Type, FormatType] & Deserializer[Type, FormatType]
object Serde:
  def apply[Type, FormatType](using
    serializer: Serializer[Type, FormatType],
    deserializer: Deserializer[Type, FormatType]
  ): Serde[Type, FormatType] =
    new Serializer[Type, FormatType] with Deserializer[Type, FormatType] {
      def serialize(value: Type): FormatType                      = serializer.serialize(value)
      def deserialize(input: FormatType): Either[Throwable, Type] = deserializer.deserialize(input)
    }

  def make[Type, FormatType](
    serializer: Serializer[Type, FormatType],
    deserializer: Deserializer[Type, FormatType]
  ): Serde[Type, FormatType] =
    new Serializer[Type, FormatType] with Deserializer[Type, FormatType] {
      def serialize(value: Type): FormatType                      = serializer.serialize(value)
      def deserialize(input: FormatType): Either[Throwable, Type] = deserializer.deserialize(input)
    }

extension [Type, FormatType](self: Serde[Type, FormatType])
  def imap[T](f: Type => T)(g: T => Type): Serde[T, FormatType] = Serde.make(self.contramap(g), self.map(f))
