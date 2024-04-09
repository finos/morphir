package morphir.hosting 
import com.sun.jna.Library
import com.sun.jna.Native


object hosting {
    def main(args: Array[String]): Unit = {
        val lib = Native.load(Platform.ifWindows( "msvcrt","c"), classOf[CMath]).asInstanceOf[CMath]
        println(lib.cosh(0))
    }
}


trait CMath extends Library {
    def cosh(value:Double):Double
}

object Platform {
    import com.sun.jna.{Platform as JNAPlatform}

    def ifWindows[T](onWindows: => T, onOther: => T):T = {
        if(JNAPlatform.isWindows()) onWindows else onOther
    }
}
