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

object Tuple {
  type Tuple[K, V] = (K, V)

  def pair[K, V](k: K)(v: V): Tuple[K, V] = (k, v)

  def first[K, V](t: Tuple[K, V]): K  = t._1
  def second[K, V](t: Tuple[K, V]): V = t._2

  def mapFirst[K, V, O](f: K => O)(t: Tuple[K, V]): Tuple[O, V]                      = pair(f(t._1))(t._2)
  def mapSecond[K, V, O](f: V => O)(t: Tuple[K, V]): Tuple[K, O]                     = pair(t._1)(f(t._2))
  def mapBoth[K, V, KO, VO](kf: K => KO)(vf: V => VO)(t: Tuple[K, V]): Tuple[KO, VO] = pair(kf(t._1))(vf(t._2))

}
