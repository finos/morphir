///|
fn option(args : Array[String], name : String, default : String) -> String {
  for i in 0..<(args.length() - 1) {
    if args[i] == name {
      return args[i + 1]
    }
  }
  default
}

///|
async fn main {
  let args = @env.args()
  let root = option(args, "--root", "../..")
  let out = option(args, "--out", "\{root}/_site")
  let main_build = args.contains("--main")
  let warnings = generate(root, out, main_build) catch {
    @model.Invalid(problems) => {
      for p in problems {
        println("error: \{p.render()}")
      }
      println("site: \{problems.length()} problem(s)")
      @sys.exit(1)
      []
    }
    error => {
      println("error: \{error}")
      @sys.exit(1)
      []
    }
  }
  for w in warnings {
    println("warning: \{w.render()}")
  }
  println("site: wrote \{out}")
}
