package org.finos.morphir.std.convert
import utest.* 
object FromSpec extends TestSuite {
  val tests = Tests {
    test("From can convert things which have the Conversion trait defined") {
        def verifyFromWorks[Src,Dst](input:Src, maybeExpected:Option[Dst] = None)(using from:From[Src,Dst], convert:Conversion[Src,Dst]) =
            maybeExpected match {
                case Some(expected) => assert(from(input) == convert(input), from(input) == expected)  
                case None => assert(from(input) == convert(input))
            }

        test { verifyFromWorks(1:Int, Some(1:Long)) }

    }
  }
}
