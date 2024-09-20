package org.finos.morphir.config

import kyo.*
import org.finos.morphir.api.*
import org.finos.morphir.testing.*
import metaconfig.{pprint as _, *}
import metaconfig.sconfig.*
import zio.test.{Result as _, *}
import neotype.*
import neotype.interop.jsoniter.given
import com.github.plokhotnyuk.jsoniter_scala.macros.*
import com.github.plokhotnyuk.jsoniter_scala.core.*
import com.github.plokhotnyuk.jsoniter_scala.macros.JsonCodecMaker.*

object JsonSerializationAndDeserializationSpec extends MorphirSpecDefault:

  enum ElmProjectLite:
    case Application(version: String, sourceDirectories: List[String], dependencies: Map[String, String])
    case Package(version: SemVerString, exposedModules: List[String], dependencies: Map[String, String])
  object ElmProjectLite:
    given jsonCodec: JsonValueCodec[ElmProjectLite] =
      JsonCodecMaker.makeWithoutDiscriminator[ElmProjectLite]

  def spec = suite("Json Serialization and Deserialization")(
    test("Should be able to serialize and deserialize an ElmProjectLite of type Application") {
      val project: ElmProjectLite = ElmProjectLite.Application(
        version = "1.0.0",
        sourceDirectories = List("src"),
        dependencies = Map("a" -> "1.0.0", "b" -> "2.0.0")
      )
      val json: String = writeToString(project)
      pprint.log(json)
      val expected =
        """{"Application":{"version":"1.0.0","sourceDirectories":["src"],"dependencies":{"a":"1.0.0","b":"2.0.0"}}}"""
      assertTrue(json == expected)
      val deserialized: ElmProjectLite = readFromString[ElmProjectLite](json)
      assertTrue(deserialized == project)
    },
    test("Should be able to serialize and deserialize an ElmProjectLite of type Package") {
      val project: ElmProjectLite = ElmProjectLite.Package(
        version = SemVerString("1.0.0"),
        exposedModules = List("Main"),
        dependencies = Map("a" -> "1.0.0", "b" -> "2.0.0")
      )
      val json: String = writeToString(project)
      pprint.log(json)
      val expected =
        """{"Package":{"version":"1.0.0","exposedModules":["Main"],"dependencies":{"a":"1.0.0","b":"2.0.0"}}}"""
      assertTrue(json == expected)
      val deserialized: ElmProjectLite = readFromString[ElmProjectLite](json)
      assertTrue(deserialized == project)
    }
  )
end JsonSerializationAndDeserializationSpec
