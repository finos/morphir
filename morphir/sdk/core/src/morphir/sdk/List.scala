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

import morphir.sdk.Basics.Bool
import morphir.sdk.Maybe.{ Just, Maybe }

object List {
  type List[+A] = scala.List[A]

  @inline def all[A](predicate: A => Boolean)(xs: List[A]): Boolean =
    xs.forall(predicate)

  @inline def any[A](predicate: A => Boolean)(xs: List[A]): Boolean =
    xs.exists(predicate)

  @inline def append[A](xs: List[A])(ys: List[A]): List[A] =
    xs ++ ys

  def apply[A](items: A*): List[A] =
    scala.List(items: _*)

  @inline def concat[A](lists: List[List[A]]): List[A] =
    lists.flatten

  @inline def concatMap[A, B](f: A => List[B])(lists: List[A]): List[B] =
    lists.flatMap(f)

  @inline def cons[A](head: A)(tail: List[A]): List[A] = head :: tail

  @inline def drop[A](n: Int)(xs: List[A]): List[A] = xs.drop(n)

  @inline def empty[A]: List[A] = Nil

  @inline def filter[A](f: A => Boolean)(xs: List[A]): List[A] =
    xs.filter(f)

  def filterMap[A, B](f: A => Maybe[B])(xs: List[A]): List[B] =
    xs.map(f).collect { case Just(value) => value }

  def foldl[A, B](f: A => B => B)(initial: B)(xs: List[A]): B = {
    def fn(b: B, a: A): B = f(a)(b)
    xs.foldLeft(initial)(fn)
  }

  def foldr[A, B](f: A => B => B)(initial: B)(xs: List[A]): B = {
    def fn(a: A, b: B): B = f(a)(b)
    xs.foldRight(initial)(fn)
  }

  @inline def head[A](xs: List[A]): Maybe[A] = xs.headOption

  def indexedMap[X, R](fn: Int => X => R)(xs: List[X]): List[R] =
    xs.zipWithIndex.map(tuple => fn(tuple._2)(tuple._1))

  def intersperse[A](elem: A)(xs: List[A]): List[A] = xs match {
    case lst if lst == Nil => lst
    case lst @ _ :: Nil    => lst
    case lst =>
      lst.take(xs.length - 1).flatMap(x => List(x, elem)) ++ List(xs.last)
  }

  @inline def length[A](xs: List[A]): Int    = xs.length
  @inline def singleton[A](item: A): List[A] = scala.List(item)

  @inline def map[A, B](mapping: A => B)(list: List[A]): List[B] =
    list.map(mapping)

  /** Combine two lists, combining them with the given function. If one list is longer, the extra elements are dropped.
    * @param mapping
    *   a mapping function
    * @param xs
    *   the first list
    * @param ys
    *   the second list
    * @tparam A
    *   the type of the first list
    * @tparam B
    *   the type of the second list
    * @tparam R
    *   the type of the resulting list
    * @return
    *   a list containing the combined elements of list1 and list2 using the mapping function.
    */
  def map2[A, B, R](
    mapping: A => B => R
  )(xs: List[A])(ys: List[B]): List[R] =
    xs.zip(ys).map { case (a, b) =>
      mapping(a)(b)
    }

  def map3[X, Y, Z, R](
    mapping: X => Y => Z => R
  )(xs: List[X])(ys: List[Y])(zs: List[Z]): List[R] =
    xs.zip(ys).zip(zs).map { case ((x, y), z) =>
      mapping(x)(y)(z)
    }

  def map4[A, B, C, D, R](
    mapping: A => B => C => D => R
  )(as: List[A])(bs: List[B])(cs: List[C])(ds: List[D]): List[R] =
    as.zip(bs).zip(cs).zip(ds).map { case (((a, b), c), d) =>
      mapping(a)(b)(c)(d)
    }

  def map5[A, B, C, D, E, R](
    mapping: A => B => C => D => E => R
  )(as: List[A])(bs: List[B])(cs: List[C])(ds: List[D])(es: List[E]): List[R] =
    as.zip(bs)
      .zip(cs)
      .zip(ds)
      .zip(es)
      .map { case ((((a, b), c), d), e) =>
        mapping(a)(b)(c)(d)(e)
      }

  @inline def member[A, A1 >: A](candidate: A1)(xs: List[A]): Boolean =
    xs.contains(candidate)

  @inline def isEmpty[A](list: List[A]): Boolean = list.isEmpty

  @inline def partition[A](f: A => Boolean)(xs: List[A]): (List[A], List[A]) =
    xs.partition(f)

  @inline def range(start: Int)(end: Int): List[Int] =
    scala.List.range(start, end)

  @inline def repeat[A](n: Int)(elem: => A): List[A] =
    scala.List.fill(n)(elem)

  @inline def reverse[A](xs: List[A]): List[A] = xs.reverse

  @inline def tail[A](xs: List[A]): Maybe[List[A]] = xs.tail match {
    case Nil  => Maybe.Nothing
    case tail => Maybe.Just(tail)
  }

  @inline def take[A](n: Int)(xs: List[A]): List[A] = xs.take(n)

  @inline def unzip[A, B](xs: List[(A, B)]): (List[A], List[B]) =
    xs.unzip

  @inline def minimum[A: Ordering](list: List[A]): Maybe[A] =
    if (list.isEmpty) Maybe.Nothing else Maybe.Just(list.min)
  @inline def maximum[A: Ordering](list: List[A]): Maybe[A] =
    if (list.isEmpty) Maybe.Nothing else Maybe.Just(list.max)
  @inline def sum[A: Numeric](list: List[A]): A     = list.sum
  @inline def product[A: Numeric](list: List[A]): A = list.product

  def innerJoin[A, B](listB: List[B])(f: A => B => Bool)(listA: List[A]): List[(A, B)] =
    for {
      itemA <- listA
      itemB <- listB
      if f(itemA)(itemB)
    } yield (itemA, itemB)

  def leftJoin[A, B](listB: List[B])(f: A => B => Bool)(listA: List[A]): List[(A, Maybe[B])] =
    listA.flatMap { itemA =>
      val filteredListB = listB.filter(f(itemA))
      if (filteredListB.isEmpty) {
        scala.List((itemA, Maybe.nothing))
      } else {
        for {
          itemB <- filteredListB
        } yield (itemA, Maybe.just(itemB))
      }
    }
}
