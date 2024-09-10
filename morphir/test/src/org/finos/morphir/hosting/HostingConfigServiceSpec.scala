package org.finos.morphir.hosting

import kyo.*
import org.finos.morphir.testing.*
import zio.test.*

object HostingConfigServiceSpec extends MorphirKyoSpecDefault:
    def spec = suite("HostingConfigServiceSpec")(
        test("applicationConfigDir should return a path") {
            val service = HostingConfigService.Live()
            service.applicationConfigDir.map { path => 
                pprint.log(path)                
                assertTrue(path != null)
            }            
        }        
    )
