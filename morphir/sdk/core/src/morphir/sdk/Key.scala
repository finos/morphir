package morphir.sdk

import scala.annotation.nowarn

/** This class is mostly generated. The code to generate it is in the comments below.
  */
object Key {

//    object GenKey {
//
//        def main(args: Array[String]): Unit = {
//            for {
//                n <- 2 to 16
//            } {
//                val typeArgs = (1 to n).map(x => s"K$x").mkString(", ")
//
//                val elems = (1 to n).map(x => s"K$x").mkString(", ")
//
//                println(s"  type Key$n[$typeArgs] = ($elems)")
//                println()
//            }
//
//            for {
//                n <- 2 to 16
//            } {
//                val typeArgs = (1 to n).map(x => s"B$x").mkString(", ")
//
//                val args = (1 to n).map(x => s"k$x: A => B$x").mkString("(", ")(", ")")
//
//                val elems = (1 to n).map(x => s"k$x(a)").mkString(", ")
//
//                println(s"  def key$n[A, $typeArgs]$args(a: A): Key$n[$typeArgs] =")
//                println(s"    ($elems)")
//                println()
//            }
//        }
//
//    }

  type Key0 = morphir.sdk.Basics.Int

  def noKey[A](a: A): Key0 =
    key0(a)

  def key0[A](@nowarn a: A): Key0 =
    0

  type Key2[K1, K2] = (K1, K2)

  type Key3[K1, K2, K3] = (K1, K2, K3)

  type Key4[K1, K2, K3, K4] = (K1, K2, K3, K4)

  type Key5[K1, K2, K3, K4, K5] = (K1, K2, K3, K4, K5)

  type Key6[K1, K2, K3, K4, K5, K6] = (K1, K2, K3, K4, K5, K6)

  type Key7[K1, K2, K3, K4, K5, K6, K7] = (K1, K2, K3, K4, K5, K6, K7)

  type Key8[K1, K2, K3, K4, K5, K6, K7, K8] = (K1, K2, K3, K4, K5, K6, K7, K8)

  type Key9[K1, K2, K3, K4, K5, K6, K7, K8, K9] = (K1, K2, K3, K4, K5, K6, K7, K8, K9)

  type Key10[K1, K2, K3, K4, K5, K6, K7, K8, K9, K10] = (K1, K2, K3, K4, K5, K6, K7, K8, K9, K10)

  type Key11[K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11] = (K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11)

  type Key12[K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12] = (K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12)

  type Key13[K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13] =
    (K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13)

  type Key14[K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13, K14] =
    (K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13, K14)

  type Key15[K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13, K14, K15] =
    (K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13, K14, K15)

  type Key16[K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13, K14, K15, K16] =
    (K1, K2, K3, K4, K5, K6, K7, K8, K9, K10, K11, K12, K13, K14, K15, K16)

  def key2[A, B1, B2](k1: A => B1)(k2: A => B2)(a: A): Key2[B1, B2] =
    (k1(a), k2(a))

  def key3[A, B1, B2, B3](k1: A => B1)(k2: A => B2)(k3: A => B3)(a: A): Key3[B1, B2, B3] =
    (k1(a), k2(a), k3(a))

  def key4[A, B1, B2, B3, B4](k1: A => B1)(k2: A => B2)(k3: A => B3)(k4: A => B4)(a: A): Key4[B1, B2, B3, B4] =
    (k1(a), k2(a), k3(a), k4(a))

  def key5[A, B1, B2, B3, B4, B5](k1: A => B1)(k2: A => B2)(k3: A => B3)(k4: A => B4)(k5: A => B5)(
    a: A
  ): Key5[B1, B2, B3, B4, B5] =
    (k1(a), k2(a), k3(a), k4(a), k5(a))

  def key6[A, B1, B2, B3, B4, B5, B6](k1: A => B1)(k2: A => B2)(k3: A => B3)(k4: A => B4)(k5: A => B5)(k6: A => B6)(
    a: A
  ): Key6[B1, B2, B3, B4, B5, B6] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a))

  def key7[A, B1, B2, B3, B4, B5, B6, B7](k1: A => B1)(k2: A => B2)(k3: A => B3)(k4: A => B4)(k5: A => B5)(k6: A => B6)(
    k7: A => B7
  )(a: A): Key7[B1, B2, B3, B4, B5, B6, B7] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a))

  def key8[A, B1, B2, B3, B4, B5, B6, B7, B8](k1: A => B1)(k2: A => B2)(k3: A => B3)(k4: A => B4)(k5: A => B5)(
    k6: A => B6
  )(k7: A => B7)(k8: A => B8)(a: A): Key8[B1, B2, B3, B4, B5, B6, B7, B8] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a))

  def key9[A, B1, B2, B3, B4, B5, B6, B7, B8, B9](k1: A => B1)(k2: A => B2)(k3: A => B3)(k4: A => B4)(k5: A => B5)(
    k6: A => B6
  )(k7: A => B7)(k8: A => B8)(k9: A => B9)(a: A): Key9[B1, B2, B3, B4, B5, B6, B7, B8, B9] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a), k9(a))

  def key10[A, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10](k1: A => B1)(
    k2: A => B2
  )(k3: A => B3)(k4: A => B4)(k5: A => B5)(k6: A => B6)(k7: A => B7)(k8: A => B8)(k9: A => B9)(k10: A => B10)(
    a: A
  ): Key10[B1, B2, B3, B4, B5, B6, B7, B8, B9, B10] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a), k9(a), k10(a))

  def key11[A, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11](k1: A => B1)(k2: A => B2)(
    k3: A => B3
  )(k4: A => B4)(k5: A => B5)(k6: A => B6)(k7: A => B7)(k8: A => B8)(k9: A => B9)(k10: A => B10)(k11: A => B11)(
    a: A
  ): Key11[B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a), k9(a), k10(a), k11(a))

  def key12[A, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12](k1: A => B1)(k2: A => B2)(k3: A => B3)(
    k4: A => B4
  )(k5: A => B5)(k6: A => B6)(k7: A => B7)(k8: A => B8)(k9: A => B9)(k10: A => B10)(k11: A => B11)(k12: A => B12)(
    a: A
  ): Key12[B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a), k9(a), k10(a), k11(a), k12(a))

  def key13[A, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13](k1: A => B1)(k2: A => B2)(k3: A => B3)(
    k4: A => B4
  )(k5: A => B5)(k6: A => B6)(k7: A => B7)(k8: A => B8)(k9: A => B9)(k10: A => B10)(k11: A => B11)(k12: A => B12)(
    k13: A => B13
  )(a: A): Key13[B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a), k9(a), k10(a), k11(a), k12(a), k13(a))

  def key14[A, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13, B14](k1: A => B1)(k2: A => B2)(k3: A => B3)(
    k4: A => B4
  )(k5: A => B5)(k6: A => B6)(k7: A => B7)(k8: A => B8)(k9: A => B9)(k10: A => B10)(k11: A => B11)(k12: A => B12)(
    k13: A => B13
  )(k14: A => B14)(a: A): Key14[B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13, B14] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a), k9(a), k10(a), k11(a), k12(a), k13(a), k14(a))

  def key15[A, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13, B14, B15](k1: A => B1)(k2: A => B2)(k3: A => B3)(
    k4: A => B4
  )(k5: A => B5)(k6: A => B6)(k7: A => B7)(k8: A => B8)(k9: A => B9)(k10: A => B10)(k11: A => B11)(k12: A => B12)(
    k13: A => B13
  )(k14: A => B14)(k15: A => B15)(a: A): Key15[B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13, B14, B15] =
    (k1(a), k2(a), k3(a), k4(a), k5(a), k6(a), k7(a), k8(a), k9(a), k10(a), k11(a), k12(a), k13(a), k14(a), k15(a))

  def key16[A, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13, B14, B15, B16](
    k1: A => B1
  )(k2: A => B2)(k3: A => B3)(k4: A => B4)(
    k5: A => B5
  )(k6: A => B6)(k7: A => B7)(k8: A => B8)(k9: A => B9)(k10: A => B10)(k11: A => B11)(k12: A => B12)(k13: A => B13)(
    k14: A => B14
  )(k15: A => B15)(k16: A => B16)(a: A): Key16[B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13, B14, B15, B16] =
    (
      k1(a),
      k2(a),
      k3(a),
      k4(a),
      k5(a),
      k6(a),
      k7(a),
      k8(a),
      k9(a),
      k10(a),
      k11(a),
      k12(a),
      k13(a),
      k14(a),
      k15(a),
      k16(a)
    )

}
