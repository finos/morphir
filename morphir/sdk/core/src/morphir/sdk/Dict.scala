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

import morphir.sdk.Maybe.Maybe

object Dict {

  type Dict[K, V] = Map[K, V]

  def empty[K, V]: Dict[K, V] = Map.empty[K, V]

  /* Build */
  def singleton[K, V](key: K)(value: V): Dict[K, V] = Map(key -> value)

  def insert[K, V](key: K)(value: V)(dict: Dict[K, V]): Dict[K, V] =
    dict + (key -> value)

  def update[K, V](targetKey: K)(alter: Maybe[V] => Maybe[V])(dict: Dict[K, V]): Dict[K, V] =
    alter(dict.get(targetKey)) match {
      case Maybe.Just(updatedValue) => dict.updated(targetKey, updatedValue)
      case Maybe.Nothing            => dict
    }

  def remove[K, V](targetKey: K)(dict: Dict[K, V]): Dict[K, V] = dict.-(targetKey)

  /* Query*/
  def isEmpty[K, V](dict: Dict[K, V]): Boolean =
    dict.isEmpty

  def member[K, V](key: K)(dict: Dict[K, V]): Boolean =
    dict.contains(key)

  def get[K, V](targetKey: K)(dict: Dict[K, V]): Maybe[V] =
    dict.get(targetKey)

  def size[K, V](dict: Dict[K, V]): Int = dict.size

  /* List */
  def keys[K, V](dict: Dict[K, V]): List[K] = dict.keys.toList

  def values[K, V](dict: Dict[K, V]): List[V] = dict.values.toList

  def toList[K, V](dict: Dict[K, V]): List[(K, V)] =
    dict.toList

  def fromList[K, V](assocs: List[(K, V)]): Dict[K, V] =
    assocs.toMap

  /* Transform */
  def map[K, V, B](f: K => V => B)(dict: Dict[K, V]): Dict[K, B] = dict.map(x => (x._1, f(x._1)(x._2)))

  def foldl[K, V, B](f: K => V => B => B)(initValue: B)(dict: Dict[K, V]): B =
    dict.foldLeft(initValue)((accumulator, pairedValues) => f(pairedValues._1)(pairedValues._2)(accumulator))

  def foldr[K, V, B](f: K => V => B => B)(initValue: B)(dict: Dict[K, V]): B =
    dict.foldRight(initValue)((a, accumulator) => f(a._1)(a._2)(accumulator))

  def filter[K, V](f: K => V => Boolean)(dict: Dict[K, V]): Dict[K, V] = dict.filter(x => f(x._1)(x._2))

  def partition[K, V](f: K => V => Boolean)(dict: Dict[K, V]): (Dict[K, V], Dict[K, V]) =
    dict.partition(x => f(x._1)(x._2))

  /* Combine */
  def union[K, V](dictToMerged: Dict[K, V])(dict: Dict[K, V]): Dict[K, V] = dict ++ dictToMerged

  def intersect[K, V](dictToIntersect: Dict[K, V])(dict: Dict[K, V]): Dict[K, V] =
    dict.toSet.intersect(Dict.toList(dictToIntersect).toSet).toMap

  def diff[K, V](dictToDiff: Dict[K, V])(dict: Dict[K, V]): Dict[K, V] =
    dictToDiff -- dict.keySet

  object tupled {

    @inline def get[K, V](targetKey: K, dict: Dict[K, V]): Maybe[V] =
      Dict.get(targetKey)(dict)

    @inline def member[K, V](key: K, dict: Dict[K, V]): Boolean =
      Dict.member(key)(dict)

    @inline def insert[K, V](
      key: K,
      value: V,
      dict: Dict[K, V]
    ): Dict[K, V] =
      Dict.insert(key)(value)(dict)
  }
}
