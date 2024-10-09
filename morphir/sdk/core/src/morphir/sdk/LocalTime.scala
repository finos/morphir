package morphir.sdk

import java.time.temporal.ChronoUnit

object LocalTime {

  type LocalTime = java.time.LocalTime

  def addHours(hours: Basics.Int)(localTime: LocalTime): LocalTime =
    localTime.plusHours(hours.toLong)

  def addMinute(minutes: Basics.Int)(localTime: LocalTime): LocalTime =
    localTime.plusMinutes(minutes.toLong)

  def addSeconds(seconds: Basics.Int)(localTime: LocalTime): LocalTime =
    localTime.plusSeconds(seconds.toLong)

  def diffInHours(localTime1: LocalTime)(localTime2: LocalTime): Basics.Int =
    ChronoUnit.HOURS.between(localTime1, localTime2).toInt

  def diffInMinutes(localTime1: LocalTime)(localTime2: LocalTime): Basics.Int =
    ChronoUnit.MINUTES.between(localTime1, localTime2).toInt

  def diffInSeconds(localTime1: LocalTime)(localTime2: LocalTime): Basics.Int =
    ChronoUnit.SECONDS.between(localTime1, localTime2).toInt

}
