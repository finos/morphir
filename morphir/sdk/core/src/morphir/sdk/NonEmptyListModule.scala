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

import morphir.sdk.NonEmptyListModule.NonEmptyList.{ Cons, Single }

import scala.annotation.tailrec

object NonEmptyListModule {
  sealed trait NonEmptyList[+A] { self =>
    @tailrec
    final def foldLeft[B](z: B)(f: (B, A) => B): B =
      self match {
        case Cons(h, t) => t.foldLeft(f(z, h))(f)
        case Single(h)  => f(z, h)
      }
  }

  object NonEmptyList {
    final case class Cons[+A](head: A, tail: NonEmptyList[A]) extends NonEmptyList[A]
    final case class Single[+A](head: A)                      extends NonEmptyList[A]
  }
}
