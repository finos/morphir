package org.finos.morphir.hosting

import kyo.*
import org.finos.morphir.testing.*
import zio.test.*

object HostingConfigServiceSpec extends MorphirKyoSpecDefault:
    def spec = suite("HostingConfigServiceSpec")(
        test("applicationConfigDir should return a path") {
            val service = HostingConfigService.Live()
            for {
                path <- service.applicationConfigDir
                lastPart = path.path.lastOption.map(_.toLowerCase)
                
                //_ <- Console.println(pprint(path))                
            } yield assertTrue(path != null, lastPart.get.endsWith("morphir"))
                     
        }        
    )
