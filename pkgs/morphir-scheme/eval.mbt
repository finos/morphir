///|
pub fn proper(datum : Datum) -> Array[Datum] raise SchemeError {
  match datum {
    Sequence(items, None) => items
    _ => raise Invalid("Expected proper syntax list")
  }
}

///|
pub fn symbol(datum : Datum) -> String raise SchemeError {
  match datum {
    Symbol(name) => name
    _ => raise Invalid("Expected identifier")
  }
}

///|
fn formals(datum : Datum) -> (Array[String], String?) raise SchemeError {
  let (params, rest) = match datum {
    Symbol(name) => ([], Some(name))
    Sequence(params, tail) => (params.map(symbol), tail.map(symbol))
    _ => raise Invalid("Invalid lambda formals")
  }
  let seen : Map[String, Bool] = Map([])
  for name in params {
    if seen.contains(name) {
      raise Invalid("Duplicate parameter: " + name)
    }
    seen[name] = true
  }
  if rest is Some(name) && seen.contains(name) {
    raise Invalid("Duplicate rest parameter: " + name)
  }
  (params, rest)
}

///|
fn Runtime::bind(
  self : Runtime,
  closure : Closure,
  args : Array[Value],
) -> Int32 raise SchemeError {
  if closure.owner != self.owner {
    raise Invalid("Closure belongs to another runtime")
  }
  if args.length() < closure.parameters.length() ||
    (closure.rest is None && args.length() != closure.parameters.length()) {
    raise Invalid("Procedure argument count mismatch")
  }
  let env = self.frame(closure.environment)
  for i, name in closure.parameters {
    self.frames[env].bindings[name] = args[i]
  }
  if closure.rest is Some(name) {
    self.frames[env].bindings[name] = list(
      args[closure.parameters.length():].to_owned(),
    )
  }
  env
}

///|
fn Runtime::sequence(
  self : Runtime,
  body : Array[Datum],
  env : Int32,
) -> Value raise {
  if body.is_empty() {
    return Unit
  }
  let mut result = Unit
  for form in body {
    result = self.evaluate(form, env)
  }
  result
}

///|
fn Runtime::evaluate(
  self : Runtime,
  datum : Datum,
  environment : Int32,
) -> Value raise {
  self.depth += 1
  defer {
    self.depth -= 1
  }
  if self.depth > self.limits.depth {
    raise Limit("evaluation depth")
  }
  self.evaluate_loop(datum, environment)
}

///|
fn Runtime::evaluate_loop(
  self : Runtime,
  datum : Datum,
  environment : Int32,
) -> Value raise {
  let mut current = datum
  let mut env = environment
  for ;; {
    self.tick()
    let forms = match current {
      Symbol(name) => return self.lookup_in(env, name)
      Sequence(items, None) => items
      Sequence(_, Some(_)) =>
        raise Invalid("Cannot evaluate an improper application")
      _ => return quote(current)
    }
    if forms.is_empty() {
      raise Invalid("Empty application")
    }
    let head = match forms[0] {
      Symbol(name) => name
      _ => ""
    }
    match head {
      "quote" => {
        if forms.length() != 2 {
          raise Invalid("quote expects one datum")
        }
        return quote(forms[1])
      }
      "if" => {
        if forms.length() != 4 {
          raise Invalid("if expects condition, consequent and alternative")
        }
        current = if truth(self.evaluate(forms[1], env)) {
          forms[2]
        } else {
          forms[3]
        }
        continue
      }
      "begin" => {
        if forms.length() == 1 {
          return Unit
        }
        for i = 1; i < forms.length() - 1; i = i + 1 {
          ignore(self.evaluate(forms[i], env))
        }
        current = forms[forms.length() - 1]
        continue
      }
      "lambda" => {
        if forms.length() < 3 {
          raise Invalid("lambda expects parameters and body")
        }
        let (parameters, rest) = formals(forms[1])
        return Closure({
          owner: self.owner,
          environment: env,
          parameters,
          rest,
          body: forms[2:].to_owned(),
        })
      }
      "define" => {
        if forms.length() < 3 {
          raise Invalid("define expects name and value")
        }
        let (name, expression) = match forms[1] {
          Symbol(name) => {
            if forms.length() != 3 {
              raise Invalid("define expects one value")
            }
            (name, forms[2])
          }
          Sequence(signature, tail) if !signature.is_empty() => {
            let name = symbol(signature[0])
            let body = [
              Datum::Symbol("lambda"),
              Sequence(signature[1:].to_owned(), tail),
            ]
            body.append(forms[2:].to_owned())
            (name, Datum::Sequence(body, None))
          }
          _ => raise Invalid("Invalid definition")
        }
        let value = self.evaluate(expression, env)
        self.frames[env].bindings[name] = value
        return Unit
      }
      "set!" => {
        if forms.length() != 3 {
          raise Invalid("set! expects name and value")
        }
        let name = symbol(forms[1])
        let value = self.evaluate(forms[2], env)
        let mut scope = Some(env)
        while scope is Some(index) {
          if self.frames[index].pending.contains(name) {
            raise Invalid("Uninitialized recursive binding: " + name)
          }
          if self.frames[index].bindings.contains(name) {
            self.frames[index].bindings[name] = value
            return Unit
          }
          scope = self.frames[index].parent
        }
        raise Unbound(name)
      }
      "and" | "or" => {
        if forms.length() == 1 {
          return Boolean(head == "and")
        }
        for i = 1; i < forms.length() - 1; i = i + 1 {
          let value = self.evaluate(forms[i], env)
          if truth(value) == (head == "or") {
            return value
          }
        }
        current = forms[forms.length() - 1]
        continue
      }
      "let" | "let*" | "letrec" => {
        if forms.length() < 3 {
          raise Invalid("let expects bindings and body")
        }
        if head == "let" && forms[1] is Symbol(name) {
          if forms.length() < 4 {
            raise Invalid("Named let expects body")
          }
          let bindings = bindings(forms[2])
          let scope = self.frame(env)
          let closure = Closure::{
            owner: self.owner,
            environment: scope,
            parameters: bindings.map(pair => pair.0),
            rest: None,
            body: forms[3:].to_owned(),
          }
          self.frames[scope].bindings[name] = Value::Closure(closure)
          let args = bindings.map(pair => self.evaluate(pair.1, env))
          env = self.bind(closure, args)
          current = Datum::Sequence(
            [Datum::Symbol("begin"), ..closure.body],
            None,
          )
          continue
        }
        let bindings = bindings(forms[1], sequential=head == "let*")
        let mut scope = self.frame(env)
        if head == "letrec" {
          for (name, _) in bindings {
            self.frames[scope].pending[name] = true
          }
          let values = bindings.map(pair => self.evaluate(pair.1, scope))
          for i, pair in bindings {
            self.frames[scope].pending.remove(pair.0)
            self.frames[scope].bindings[pair.0] = values[i]
          }
        } else {
          for (name, expression) in bindings {
            let value = self.evaluate(
              expression,
              if head == "let" {
                env
              } else {
                scope
              },
            )
            if head == "let*" {
              scope = self.frame(scope)
            }
            self.frames[scope].bindings[name] = value
          }
        }
        env = scope
        current = Datum::Sequence([Datum::Symbol("begin"), ..forms[2:]], None)
        continue
      }
      _ => ()
    }
    let procedure = self.evaluate(forms[0], env)
    let args = forms[1:].to_owned().map(form => self.evaluate(form, env))
    match procedure {
      Closure(closure) => {
        env = self.bind(closure, args)
        for i = 0; i < closure.body.length() - 1; i = i + 1 {
          ignore(self.evaluate(closure.body[i], env))
        }
        current = closure.body[closure.body.length() - 1]
      }
      Native(name) => return self.invoke_native(name, args)
      NativeFunction(callback) => return callback(self, args)
      _ => raise Invalid("Attempt to call a non-procedure")
    }
  }
}

///|
pub fn bindings(
  datum : Datum,
  sequential~ : Bool = false,
) -> Array[(String, Datum)] raise SchemeError {
  let seen : Map[String, Bool] = Map([])
  proper(datum).map(binding => {
    let pair = proper(binding)
    if pair.length() != 2 {
      raise Invalid("Binding expects name and expression")
    }
    let name = symbol(pair[0])
    if !sequential && seen.contains(name) {
      raise Invalid("Duplicate binding: " + name)
    }
    seen[name] = true
    (name, pair[1])
  })
}

///|
fn Runtime::invoke_native(
  self : Runtime,
  name : String,
  args : Array[Value],
) -> Value raise {
  self.tick()
  if self.native_arities.get(name) is Some(expected) &&
    args.length() != expected {
    raise Invalid(name + " expects " + expected.to_string() + " arguments")
  }
  match self.natives.get(name) {
    Some(procedure) => procedure(self, args)
    None => raise Unbound(name)
  }
}

///|
pub fn Runtime::eval(self : Runtime, source : String) -> Value raise {
  let forms = parse_program(source)
  let was_active = self.active
  if !was_active {
    self.fuel = self.limits.steps
    self.active = true
  }
  defer {
    self.active = was_active
  }
  self.sequence(forms, 0)
}

///|
/// Evaluate an already read top-level form in this runtime. An enclosing
/// with_budget call shares its resource allowance across a complete worksheet.
pub fn Runtime::eval_datum(self : Runtime, form : Datum) -> Value raise {
  self.with_budget(runtime => runtime.evaluate(form, 0))
}

///|
pub fn Runtime::call(
  self : Runtime,
  procedure : Value,
  args : Array[Value],
) -> Value raise {
  let was_active = self.active
  if !was_active {
    self.fuel = self.limits.steps
    self.active = true
  }
  defer {
    self.active = was_active
  }
  self.tick()
  match procedure {
    Closure(closure) => self.sequence(closure.body, self.bind(closure, args))
    Native(name) => self.invoke_native(name, args)
    NativeFunction(callback) => callback(self, args)
    _ => raise Invalid("Expected procedure")
  }
}

///|
/// Share one cancellation and step budget across a mixed native and Scheme call.
pub fn[A] Runtime::with_budget(
  self : Runtime,
  work : (Runtime) -> A raise,
) -> A raise {
  let was_active = self.active
  if !was_active {
    self.fuel = self.limits.steps
    self.active = true
  }
  defer {
    self.active = was_active
  }
  self.tick()
  work(self)
}

///|
pub fn eval_program(source : String) -> Value raise {
  Runtime::new().eval(source)
}
