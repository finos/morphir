---
id: primitives
title: Primitive Encoding
---
The following encodings are supported from Scala values into Morphir DDL primitives:

| Morphir DDL              | Morphir DDL Type  | Scala Class         | Scala Example         |
|--------------------------|-------------------|---------------------|-----------------------|
| Data.Boolean(true)       | Concept.Boolean   | scala.Boolean       | true                  |
| Data.Byte(0xf)           | Concept.Byte      | scala.Byte          | 0xf                   |
| Data.Decimal(BigDecimal) | Concept.Decimal   | scala.BigDecimal    | BigDecimal("123")     |
| Data.Integer(BigInt)     | Concept.Integer   | scala.BigInt        | BigInt("123")         |
| Data.Int16(123)          | Concept.Int16     | scala.Short         | 123.toShort           |
| Data.Int32(123)          | Concept.Int32     | scala.Int           | 123                   |
| Data.String("value")     | Concept.String    | java.lang.String    | value                 |
| Data.LocalDate           | Concept.LocalDate | java.time.LocalDate | LocalDate(2023, 1, 1) |
