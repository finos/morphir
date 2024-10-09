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

import morphir.sdk.Basics.{ Bool, True }
import morphir.sdk.List.List
import morphir.sdk.Maybe.Maybe

object Rule {

  type Rule[A, B] = A => Maybe[B]

  def chain[A, B](rules: List[Rule[A, B]]): Rule[A, B] =
    input =>
      rules
        .find(rule => rule(input).isDefined)
        .flatMap(rule => rule(input))

  def any[A]: A => Bool =
    _ => True

  def is[A](ref: A)(input: A): Bool =
    ref == input

  def anyOf[A](ref: List[A])(input: A): Bool =
    ref.contains(input)

  def noneOf[A](ref: List[A])(input: A): Bool =
    !anyOf(ref)(input)

}
