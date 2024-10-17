/*
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 */

package morphir.sdk

import morphir.sdk.{ LocalDate => SdkDate }
import zio.test.Assertion._
import zio.test._
import morphir.testing.MorphirBaseSpec

object LocalDateSpec extends MorphirBaseSpec {
  val date = java.time.LocalDate.now

  def spec = suite("Addition") {
    suite("Add days") {
      test("Identity: Adding 0") {
        assert(SdkDate.addDays(0)(date))(equalTo(date.plusDays(0)))
      }
      test("Identity: Adding up") {
        assert(SdkDate.addDays(1)(date))(equalTo(date.plusDays(1)))
      }
      test("Identity: Adding down") {
        assert(SdkDate.addDays(-1)(date))(equalTo(date.plusDays(-1)))
      }
    }
    suite("Add weeks") {
      test("Identity: Adding 0") {
        assert(SdkDate.addWeeks(0)(date))(equalTo(date.plusWeeks(0)))
      }
      test("Identity: Adding up") {
        assert(SdkDate.addWeeks(1)(date))(equalTo(date.plusWeeks(1)))
      }
      test("Identity: Adding down") {
        assert(SdkDate.addWeeks(-1)(date))(equalTo(date.plusWeeks(-1)))
      }
    }
    suite("Add months") {
      test("Identity: Adding 0") {
        assert(SdkDate.addMonths(0)(date))(equalTo(date.plusMonths(0)))
      }
      test("Identity: Adding up") {
        assert(SdkDate.addMonths(1)(date))(equalTo(date.plusMonths(1)))
      }
      test("Identity: Adding down") {
        assert(SdkDate.addMonths(-1)(date))(equalTo(date.plusMonths(-1)))
      }
    }
    suite("Add years") {
      test("Identity: Adding 0") {
        assert(SdkDate.addYears(0)(date))(equalTo(date.plusYears(0)))
      }
      test("Identity: Adding up") {
        assert(SdkDate.addYears(1)(date))(equalTo(date.plusYears(1)))
      }
      test("Identity: Adding down") {
        assert(SdkDate.addYears(-1)(date))(equalTo(date.plusYears(-1)))
      }
    }
    suite("Diff days") {
      test("Identity: diff self") {
        assert(SdkDate.diffInDays(date)(date))(equalTo(0))
      }
      test("Identity: diff later") {
        assert(SdkDate.diffInDays(date)(date.plusDays(1)))(equalTo(1))
      }
      test("Identity: diff earlier") {
        assert(SdkDate.diffInDays(date)(date.plusDays(-1)))(equalTo(-1))
      }
    }
    suite("Diff weeks") {
      test("Identity: diff self") {
        assert(SdkDate.diffInWeeks(date)(date))(equalTo(0))
      }
      test("Identity: diff later") {
        assert(SdkDate.diffInWeeks(date)(date.plusWeeks(1)))(equalTo(1))
      }
      test("Identity: diff earlier") {
        assert(SdkDate.diffInWeeks(date)(date.plusWeeks(-1)))(equalTo(-1))
      }
    }
    suite("Diff days") {
      test("Identity: diff self") {
        assert(SdkDate.diffInMonths(date)(date))(equalTo(0))
      }
      test("Identity: diff later") {
        assert(SdkDate.diffInMonths(date)(date.plusMonths(1)))(equalTo(1))
      }
      test("Identity: diff earlier") {
        assert(SdkDate.diffInMonths(date)(date.plusMonths(-1)))(equalTo(-1))
      }
    }
    suite("Diff days") {
      test("Identity: diff self") {
        assert(SdkDate.diffInYears(date)(date))(equalTo(0))
      }
      test("Identity: diff later") {
        assert(SdkDate.diffInYears(date)(date.plusYears(1)))(equalTo(1))
      }
      test("Identity: diff earlier") {
        assert(SdkDate.diffInYears(date)(date.plusYears(-1)))(equalTo(-1))
      }
    }
  }

  case class Wrapped[A](value: A)
}
