package org.finos.morphir.ir.gen1

//import zio.test._
//
//object PackageModuleSpec extends MorphirSpecDefault {
//  val packageDefModules: Map[ModuleName, AccessControlled[module.Definition[Any, UType]]] =
//    Map {
//      ModuleName.fromString("blog.author.peter") -> AccessControlled.publicAccess(moduleDef)
//    }
//
//  val packageDef: Definition[Any, UType] = Definition(packageDefModules)
//
//  val packageSpecModules: Map[ModuleName, module.Specification[Any]] =
//    Map(ModuleName.fromString("blog.author.peter") -> moduleSpec)
//
//  val packageSpec: Specification[Any] = Specification(packageSpecModules)
//
//  def spec = suite("Package")(
//    suite("Definitions")(
//      test("can convert to Specification") {
//        // todo add back when TypeModule.toSpec is implemented
////        val expected = Specification(
////          Map(
////            ModuleName(Path.fromString("blog.author"), Name("peter"))
////              -> moduleDef.toSpecification
////          )
////        )
////        assertTrue(packageDef.toSpecification == expected)
//        assertTrue(1 == 1)
//      },
//      test("Look up existing Module Definition") {
//        val result = packageDef.lookupModuleDefinition(Path.fromString("blog.author.peter"))
//        assertTrue(result.equals(Some(moduleDef)))
//      },
//      test("Look up non-existent Module Definition") {
//        val result = packageDef.lookupModuleDefinition(Path.fromString("blog.post.post6234"))
//        assertTrue(result.equals(None))
//      },
//      test("Look up existing Type Definition") {
//        val result = packageDef.lookupTypeDefinition(Path.fromString("blog.author"), Name("peter"))
//        val result2 =
//          packageDef.lookupTypeDefinition(QualifiedModuleName(
//            PackageName.fromString("blog.author"),
//            ModuleName.fromString("peter")
//          ))
//
//        assertTrue(result == Some(moduleDef) && result2 == Some(moduleDef))
//      },
//      test("Look up non-existent Type Definition") {
//        val result = packageDef.lookupTypeDefinition(Path.fromString("blog.author"), Name("stephen"))
//        val result2 =
//          packageDef.lookupTypeDefinition(QualifiedModuleName(Path.fromString("blog.author"), Name("stephen")))
//
//        assertTrue(result.isEmpty && result2.isEmpty)
//      }
//    ),
//    suite("Specification")(
//      test("Can look up existing Module Specification") {
//        val result = packageSpec.lookupModuleSpecification(Path.fromString("blog.author.peter"))
//        assertTrue(result == Some(moduleSpec))
//      },
//      test("Can look up non-existent Module Specification") {
//        val result = packageSpec.lookupModuleSpecification(Path.fromString("blog.post.post73451"))
//        assertTrue(result == None)
//      },
//      test("Look up existing Type Definition") {
//        val result = packageSpec.lookupTypeSpecification(Path.fromString("blog.author"), Name("peter"))
//        val result2 =
//          packageSpec.lookupTypeSpecification(QualifiedModuleName(Path.fromString("blog.author"), Name("peter")))
//
//        assertTrue(result == Some(moduleSpec) && result2 == Some(moduleSpec))
//      },
//      test("Look up non-existent Type Definition") {
//        val result = packageSpec.lookupTypeSpecification(Path.fromString("blog.author"), Name("stephen"))
//        val result2 =
//          packageSpec.lookupTypeSpecification(QualifiedModuleName(Path.fromString("blog.author"), Name("stephen")))
//
//        assertTrue(result.isEmpty && result2.isEmpty)
//      }
//    )
//  )
//}
