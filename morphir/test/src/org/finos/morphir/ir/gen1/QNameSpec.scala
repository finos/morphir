package org.finos.morphir.ir.gen1

import org.finos.morphir.ir.gen1.naming.*
import org.finos.morphir.testing.MorphirSpecDefault
import zio.test.*

object QNameSpec extends MorphirSpecDefault {
  def spec = suite("QName")(
    suite("Creating a tuple from QName")(
      test("toTuple should provide the Path and Name as a tuple") {
        val path     = Path.fromString("ice.cream")
        val name     = Name.fromString("float")
        val expected = (path, name)
        assertTrue(QName(ModuleName(path), name).toTuple == expected)
      }
    ),
    suite("Creating a QName")(
      test("Creating a QName with a tuple") {
        val path = Path.fromString("friday")
        val name = Name.fromString("night")
        assertTrue(QName.fromTuple((path, name)) == QName(ModuleName(path), name))
      },
      test("Creating a QName from a name") {
        val path = Path.fromString("blog.Author")
        val name = Name.fromString("book")
        assertTrue(QName.fromName(path, name) == QName(ModuleName(path), name))
      }
    ),
    suite("Fetching values from QName")(
      test("localName and path") {
        val path = Path.fromString("path")
        val name = Name.fromString("name")
        assertTrue(
          QName.getLocalName(QName(ModuleName(path), name)) == name,
          QName.getModulePath(QName(ModuleName(path), name)) == path
        )
      }
    ),
    suite("QName and Strings")(
      test("Create String from QName") {
        val path = Path.fromString("front.page")
        val name = Name.fromString("dictionary words")
        assertTrue(QName(ModuleName(path), name).toString == "Front.Page:dictionaryWords")
      },
      test("Create QName from String") {
        val str = "Proper.Path:name"
        assertTrue(QName.fromString(str) == Some(QName(ModuleName.fromString("Proper.Path"), Name.fromString("name"))))
      },
      test("Provide an invalid String") {
        val str2 = "invalidpathname"
        assertTrue(QName.fromString(str2) == None)
      }
    )
  )
}
