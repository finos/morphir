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

object Number {

  def add[A: Numeric](left: A)(right: A)(implicit numeric: Numeric[A]): A =
    numeric.plus(left, right)

  def subtract[A](left: A)(right: A)(implicit numeric: Numeric[A]): A =
    numeric.minus(left, right)

  def multiply[A](left: A)(right: A)(implicit numeric: Numeric[A]): A =
    numeric.times(left, right)

  def abs[A](value: A)(implicit numeric: Numeric[A]): A =
    numeric.abs(value)

  def negate[A](value: A)(implicit numeric: Numeric[A]): A =
    numeric.negate(value)

}
