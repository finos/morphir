/*
Copyright 2021 Morgan Stanley

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

import morphir.sdk.Basics.Bool

object Set {
  type Set[A] = scala.collection.immutable.Set[A]
  private[morphir] val Set = scala.collection.immutable.Set

  /** Create an empty set.
    */
  @inline def empty[A]: Set[A] =
    Set.empty[A]

  /** Create a set with one value.
    */
  @inline def singleton[A](value: A): Set[A] = Set(value)

  /** Insert a value into a set.
    */
  @inline def insert[A](value: A)(set: Set[A]): Set[A] = set + value

  /** Remove a value from a set. If the value is not found, no changes are made.
    */
  @inline def remove[A](value: A)(set: Set[A]): Set[A] = set - value

  /** Determine if a set is empty.
    */
  @inline def isEmpty[A](set: Set[A]): Bool = set.isEmpty

  /** Determine if a value is in a set.
    */
  @inline def member[A](value: A)(set: Set[A]): Bool = set.contains(value)

  /** Determine the number of elements in a set.
    */
  def size[A](set: Set[A]): morphir.sdk.Basics.Int = Int(set.size)

  /** Get the union of two sets. Keep all values.
    */
  @inline def union[A](a: Set[A])(b: Set[A]): Set[A] = a union b

  /** Get the intersection of two sets. Keep all the values.
    */
  @inline def intersect[A](a: Set[A])(b: Set[A]): Set[A] = a intersect b

  /** Get the difference between the first set and the second. Keeps values that do not appear in the second set.
    */
  @inline def diff[A](a: Set[A])(b: Set[A]): Set[A] = a diff b

  /** Convert a set into a list, sorted from lowest to highest.
    */
  def toList[A: Ordering](set: Set[A]): morphir.sdk.List.List[A] = set.toList.sorted

  /** Convert a list into a set, removing any duplicates.
    */
  @inline def fromList[A](list: morphir.sdk.List.List[A]): Set[A] = list.toSet

  /** Map a function onto a set, creating a new set with no duplicates.
    */
  @inline def map[A, B](fn: A => B)(set: Set[A]): Set[B] = set.map(fn)

  /** Fold over the values in a set, in order from left to right.
    */
  def foldl[A, B](f: A => B => B)(initial: => B)(set: Set[A]): B = {
    def fn(b: B, a: A): B = f(a)(b)
    set.foldLeft(initial)(fn)
  }

  /** Fold over the values in a set, in order from right to left.
    */
  def foldr[A, B](f: A => B => B)(initial: => B)(set: Set[A]): B = {
    def fn(a: A, b: B): B = f(a)(b)
    set.foldRight(initial)(fn)
  }

  /** Only keep elements that pass the given test.
    */
  def filter[A](predicate: A => Bool)(set: Set[A]): Set[A] =
    set.filter(predicate)

  /** Create tow new sets. The first contains all the elements that passed the given test, and the second contains all
    * the elements that did not.
    */
  def partition[A](predicate: A => Bool)(set: Set[A]): (Set[A], Set[A]) =
    set.partition(predicate)
}
