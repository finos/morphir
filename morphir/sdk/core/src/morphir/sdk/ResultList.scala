package morphir.sdk

object ResultList {

  type ResultList[E, A] = List.List[Result.Result[E, A]]

  /** Turn a list of results into a single result keeping all errors.
    */
  def keepAllErrors[E, A](results: ResultList[E, A]): Result.Result[List[E], List[A]] = {
    val oks: List[A] = List.filterMap(Result.toMaybe[E, A])(results)
    val errs: List[E] = List.filterMap((result: Result[E, A]) =>
      result match {
        case Result.Err(e) => Maybe.Just(e)
        case Result.Ok(_)  => Maybe.Nothing
      }
    )(results)

    errs match {
      case Nil => Result.Ok(oks)
      case _   => Result.Err(errs)
    }
  }

}
