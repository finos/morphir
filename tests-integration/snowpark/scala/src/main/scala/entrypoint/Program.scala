package entryPoint;

import com.snowflake.snowpark._
import com.snowflake.snowpark.functions._

object Program extends App {
    println("Snowpark test program");
    implicit val session = Session.builder.configFile("session.properties").create

    val assets = session.table("EXAMPLE_ASSETS");

    companyassets.rules.DepreciationRules.usefulLifeExceeded(lit(2023))(assets).show

    session.close()
}


