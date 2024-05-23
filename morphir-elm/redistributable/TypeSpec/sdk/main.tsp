namespace Morphir.SDK;

// Basic Types
namespace Basics {
  scalar Bool extends boolean;

  scalar Int extends int64;

  scalar Float extends float64;
}

namespace String {
  scalar String extends string;
}

namespace Char {
  @maxLength(1)
  @minLength(1)
  scalar Char extends string;
}


// Advance Types
namespace Decimal {
  scalar Decimal extends numeric;
}

namespace LocalDate {
  scalar LocalDate extends plainDate;
  scalar Month extends string;
}

namespace LocalTime {
  scalar LocalTime extends plainTime;
}


// Optional Types
namespace Maybe {
  alias Maybe<T> = T | null;
}


// Collection Types
namespace List{
  alias List<T> = Array<T>;
}

namespace Set{
  alias Set<T> = Array<T>;
}

namespace Dict{
  alias Dict<K,V> = Array<[K,V]>;
}


// Composite Types
namespace Tuple{
  alias Tuple<A,B> = [A,B];
}

namespace Result{
  alias Result<E,V> = ["Err", E] | ["Ok", V];
}