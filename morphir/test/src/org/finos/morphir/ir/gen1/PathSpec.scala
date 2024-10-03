package org.finos.morphir.ir.gen1

import org.finos.morphir.testing.MorphirSpecDefault
import zio.test.*

//object PathSpec extends MorphirSpecDefault {
//  def spec = suite("Path")(
//    suite("Creating a Path from a String")(
//      test("It can be constructed from a simple string") {
//        assertTrue(Path.fromString("Person") == Path(n"person"))
//      },
//      test("It can be constructed from a long string") {
//        assertTrue(Path.fromString("She Sells Seashells") == Path(n"she sells seashells"))
//      },
//      test("It can be constructed when given a dotted string") {
//        assertTrue(Path.fromString("blog.Author") == Path(n"blog", n"author"))
//      },
//      test("It can be constructed when given a '-' separated string") {
//        assertTrue(Path.fromString("blog-Author") == Path(n"blog", Name.fromList(List("author"))))
//      },
//      test("It can be constructed when given a '/' separated string") {
//        assertTrue(Path.fromString("blog/Author") == Path(Name.fromList("blog"), Name.fromList("author")))
//      },
//      test("It can be constructed when given a '\' separated string") {
//        assertTrue(Path.fromString("blog\\Author") == Path(n"blog", n"author"))
//      },
//      test("It can be constructed when given a ':' separated string") {
//        assertTrue(Path.fromString("Morphir:SDK") == Path(n"Morphir", n"SDK"))
//      },
//      test("It can be constructed when given a ';' separated string") {
//        assertTrue(Path.fromString("Blog ; Author") == Path(n"blog", n"author"))
//      },
//      test("It can be constructed from Name arguments") {
//        assertTrue(
//          Path(Name.fromString("projectfiles"), Name.fromString("filePath")) == Path.fromList(
//            List(Name.fromList(List("projectfiles")), Name.fromList(List("file", "path")))
//          )
//        )
//      },
//      test("It can be constructed from string arguments") {
//        assertTrue(
//          Path("myCompany", "some Type") == Path.fromList(
//            Name.fromList("my", "company"),
//            Name.fromList("some", "type")
//          )
//        )
//      }
//    ),
//    suite("Transforming a Path into a String")(
//      test("Paths with period and TitleCase") {
//        val input = Path(
//          Name("foo", "bar"),
//          Name("baz")
//        )
//        assertTrue(Path.toString(Name.toTitleCase, ".", input) == "FooBar.Baz")
//      },
//      test("Paths with slash and Snake_Case") {
//        val input = Path(
//          Name("foo", "bar"),
//          Name("baz")
//        )
//        assertTrue(Path.toString(Name.toSnakeCase, "/", input) == "foo_bar/baz")
//      }
//    ),
//    suite("Transforming a Path into list of Names")(
//      test("It can be constructed using toList") {
//        assertTrue(
//          Path.toList(Path(Name("Com", "Example"), Name("Hello", "World"))) == List(
//            Name("Com", "Example"),
//            Name("Hello", "World")
//          )
//        )
//      }
//    ),
//    suite("Creating a Path from a Name")(
//      test("It can be constructed from names")(
//        assertTrue(
//          Path.root / Name("Org") / Name("Finos") == Path(Vector(Name("Org"), Name("Finos"))),
//          Path.root / Name("Alpha") / Name("Beta") / Name("Gamma") == Path(Vector(
//            Name("Alpha"),
//            Name("Beta"),
//            Name("Gamma")
//          ))
//        )
//      )
//    ),
//    suite("Checking if one Path is a prefix of another should:")(
//      test("""Return true: Given path is "foo/bar" and prefix is "foo" """) {
//        val sut    = Path.fromString("foo/bar")
//        val prefix = Path.fromString("foo")
//
//        assertTrue(Path.isPrefixOf(prefix = prefix, path = sut))
//      },
//      test("""Return false: Given path is "foo/foo" and prefix is "bar" """) {
//        val sut    = Path.fromString("foo/foo")
//        val prefix = Path.fromString("bar")
//
//        assertTrue(!Path.isPrefixOf(prefix = prefix, path = sut))
//      },
//      test("""Return true: Given equal paths""") {
//        val sut    = Path.fromString("foo/bar/baz")
//        val prefix = sut
//        assertTrue(Path.isPrefixOf(prefix = prefix, path = sut))
//      }
//    ),
//    suite("ToString")(
//      test("The standard to String should return a String representation of the path using the default PathRenderer")(
//        assertTrue(
//          Path.fromString("foo/bar/baz").toString == "Foo.Bar.Baz"
//        )
//      )
//    )
//  )
//}
