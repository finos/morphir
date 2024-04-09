package morphir.hosting 
import com.sun.jna.Library;
import com.sun.jna.Native;

object hosting {
    def main(args: Array[String]): Unit = {
        val lib = Native.load("c", classOf[CMath]).asInstanceOf[CMath]
        println(lib.cosh(0))
    }
}


trait CMath extends Library {
    def cosh(value:Double):Double
}
