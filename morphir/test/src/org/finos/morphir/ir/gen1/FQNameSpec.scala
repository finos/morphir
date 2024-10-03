package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.naming.*
import org.finos.morphir.testing.MorphirSpecDefault
import zio.test.Assertion.*
import zio.test.*

object FQNameSpec extends MorphirSpecDefault {
  def spec = suite("FQNameSpec")(
    suite("Create a FQName:")(
      test("By using a string") {
        assertTrue(
          FQName.fromString("moduleName/packageName/localName", "/") ==
            FQName(
              PackageName(Path.fromString("moduleName")),
              ModuleName(Path.fromString("packageName")),
              Name.fromString("localName")
            )
        )
      }
//      test("By using a QName with package name") {
//        implicit val packageName = PackageName.fromString("package Name")
//        val qName                = QName(Path.fromString("qualified.Name.Path"), Name.fromString("localName"))
//        assertTrue(FQName.fromQName(qName) == FQName(packageName, qName.moduleName, qName.localName))
//      },
//      test("By using a QName without package name using implicit defaults") {
//        val pkg                               = PackageName(Path.fromString("package Name"))
//        implicit val default: FQNamingOptions = FQNamingOptions(pkg, ModuleName(Path.fromString("MyModule")), ":")
//        val qName = QName(Path.fromString("qualified.Name.Path"), Name.fromString("localName"))
//        assertTrue(FQName.fromQName(qName) == FQName(pkg, ModuleName(qName.modulePath), qName.localName))
//      }
    ),
    suite("Retrieving variables should work")(
      test("Get PackagePath") {
        val fqName = FQName.fromString("moduleName/packageName/localName", "/")
        assertTrue(FQName.getPackagePath(fqName) == Path.fromString("moduleName"))
      },
      test("Get ModulePath") {
        val fqName = FQName.fromString("moduleName/packageName/localName", "/")
        assertTrue(FQName.getModulePath(fqName) == Path.fromString("packageName"))
      },
      test("Get localName") {
        val fqName = FQName.fromString("moduleName/packageName/localName", "/")
        assertTrue(FQName.getLocalName(fqName) == Name.fromString("localName"))
      }
    ),
    suite("Creating a string from FQName") {
      test("should work") {
        assertTrue(
          FQName.toString(
            FQName(
              PackageName(Path.fromString("com.example")),
              ModuleName(Path.fromString("java home")),
              Name.fromString("morphir")
            )
          ) == "Com.Example:JavaHome:morphir"
        )
      }
    },
    suite("Creating FQName from a string")(
      test("3 parameters")(
        assertTrue(
          FQName.fromString("Com.Example:JavaHome:morphir", ":") ==
            FQName(
              PackageName(Path.fromString("com.example")),
              ModuleName(Path.fromString("JavaHome")),
              Name.fromString("morphir")
            )
        )
      ),
      test("3 parameters - different splitter")(
        assertTrue(
          FQName.fromString("Com.Example;JavaHome;morphir", ";") ==
            FQName(
              PackageName(Path.fromString("com.example")),
              ModuleName(Path.fromString("JavaHome")),
              Name.fromString("morphir")
            )
        )
      ),
      test("3 parameters - with implicit FQNamingOptions") {
        implicit val default: FQNamingOptions = FQNamingOptions(PackageName(Path.empty), ModuleName(Path.empty), ";")

        assertTrue(
          FQName.fromString("Com.Example;JavaHome;morphir") ==
            FQName(
              PackageName(Path.fromString("com.example")),
              ModuleName(Path.fromString("JavaHome")),
              Name.fromString("morphir")
            )
        )
      },
      test("2 parameters")(
        assertTrue(
          FQName.fromString("scalaHome:morphir") ==
            FQName(
              PackageName(Path.empty),
              ModuleName(Path.fromString("scalaHome")),
              Name.fromString("morphir")
            )
        )
      ),
      test("2 parameters - with implicit FQNamingOptions") {
        implicit val default: FQNamingOptions =
          FQNamingOptions(PackageName(Path.fromString("zio.test")), ModuleName(Path.fromString("MyModule")), ";")

        assertTrue(
          FQName.fromString("JavaHome;morphir") ==
            FQName(
              PackageName(Path.fromString("zio.test")),
              ModuleName(Path.fromString("JavaHome")),
              Name.fromString("morphir")
            )
        )
      },
      test("1 parameter")(
        assertTrue(
          FQName.fromString("morphir") == FQName(
            PackageName(Path.empty),
            ModuleName(Path.empty),
            Name.fromString("morphir")
          )
        )
      ),
      test("1 parameters - with implicit FQNamingOptions") {
        implicit val default: FQNamingOptions =
          FQNamingOptions(PackageName(Path.fromString("zio.test")), ModuleName(Path.fromString("MyModule")), ";")

        assertTrue(
          FQName.fromString("morphir") ==
            FQName(
              PackageName(Path.fromString("zio.test")),
              ModuleName(Path.fromString("MyModule")),
              Name.fromString("morphir")
            )
        )
      },
      test("empty string - empty path")(
        assertTrue(
          FQName.fromString("") ==
            FQName(
              PackageName(Path.empty),
              ModuleName(Path.empty),
              Name.fromString("")
            )
        )
      )
//      test("4 or more parameters - throws ParserError")(
//        assert(FQName.fromString("abc:bcd:cde:def", ":"))(throwsA[ParserError]) &&
//        assert(FQName.fromString("abc:bcd:cde:def:efg", ":"))(throwsA[ParserError])
//      ),
//      test("other variations for throwing ParserError")(
//        assert(FQName.fromString(":", ":"))(throwsA[ParserError]) &&
//        assert(FQName.fromString(":"))(throwsA[ParserError]) &&
//        assert(FQName.fromString("-", "-"))(throwsA[ParserError]) &&
//        assert(FQName.fromString("::", ":"))(throwsA[ParserError]) &&
//        assert(FQName.fromString("::"))(throwsA[ParserError]) &&
//        assert(FQName.fromString(";;", ";"))(throwsA[ParserError])
//      )
    )
//    suite("getModuleName")(
//      test("When Path and LocalName are compound") {
//        val sut = FQName.fromString(":morphir.sdk:local.date")
//        assertTrue(
//          sut.getModuleName == QualifiedModuleName(Path.fromString("morphir.sdk"), Name.fromString("LocalDate"))
//        )
//      }
//    )
  )
}
