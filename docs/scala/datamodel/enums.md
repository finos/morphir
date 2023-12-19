---
id: enums
title: Enum (Discriminated Union) Encoding
---
Given the following Scala types and values:
```scala
// Types:
case class OneStreamSink(topic: String)
sealed trait Sink
object Sink {
  case class OneStream(sinkData: OneStreamSink) extends Sink
  case object ConsoleLog extends Sink
}

// Values:
val os = Sink.OneStream(OneStreamSink(topic = "123"))
val oc = Sink.ConsoleLog
```
and the equivalent in Morphir/ELM:
```elm
-- Types
type alias OneStreamSink = { topic: String }
type Sink =
  OneStream {- sinkData: -} OneStreamSink
  | ConsoleLog

-- Values:
os: Sink
os = OneStream { topic = "123" }

oc: Sink
oc = ConsoleLog
```

The value `os` would be represented in the Morphir data-model as the following:
```scala
val os = Data.Case(
  values = List(
    EnumLabel.Named("sinkData") -> 
      Data.Record(L("topic") -> Data.String("123")) 
  )
  enumLabel = "OneStream",
  shape = enumConcept /* will be described in just a minute */
)
```

Note how the OneStream enum fields `sinkData` is represented as `EnumLabel.Named("sinkData")`. Not all languages 
support the naming for enum fields. As you can see in the Morphir/ELM example abovem it is commented out. Therefore
instead of `EnumLabel.Named("sinkData")` in the Moprhir-data model, it would be represented as `EnumLabel.Empty`.
```scala
val os = Data.Case(
  values = List(
    EnumLabel.Empty -> 
      Data.Record(L("topic") -> Data.String("123")) 
  )
  enumLabel = "OneStream",
  shape = enumConcept /* will be described in just a minute */
)
```

The value `oc` would be represented as the following:
```scala
// val oc: Sink = Sink.ConsoleLog // (Scala)
// oc = ConsoleLog                // (Morphir/ELM)

val oc = Data.Case(
  values = List()
  enumLabel = "ConsoleLog",
  shape = enumConcept /* will be described in just a minute */
)
```

On a schema-level the `Concept` for this enum would be the following:
```scala
Concept.Enum(
  name = "Sink",
  cases = List(
    Concept.Enum.Case(
      L("OneStream"),
      fields = List(
        EnumLabel.Named("sinkData") -> 
          Concept.Record(L("topic") -> Concept.String)
      )
    ),
    Concept.Enum.Case(
      L("ConsoleLog"),
      fields = List()
    )    
  )
)
```
