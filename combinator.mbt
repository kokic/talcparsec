///|
pub fn[I : Cursor, T, U] Parser::bind(
  self : Parser[I, T],
  next : (T) -> Parser[I, U],
) -> Parser[I, U] {
  Parser::new(input => {
    self
    .run(input)
    .bind(result => {
      let (value, rest) = result
      next(value)
      .run(rest)
      .map_err(error => {
        guard rest.cursor() != input.cursor() else { error }
        error.with_commit()
      })
    })
  })
}

///|
pub fn[I : Cursor, T, U] Parser::map(
  self : Parser[I, T],
  f : (T) -> U,
) -> Parser[I, U] {
  self.bind(value => pure(f(value)))
}

///|
pub fn[I : Cursor, T, U] Parser::then(
  self : Parser[I, T],
  next : Parser[I, U],
) -> Parser[I, U] {
  self.bind(_ => next)
}

///|
pub fn[I : Cursor, T, U] Parser::skip(
  self : Parser[I, T],
  next : Parser[I, U],
) -> Parser[I, T] {
  self.bind(value => next.map(_ => value))
}

///|
pub fn[I, T] Parser::or(
  self : Parser[I, T],
  other : Parser[I, T],
) -> Parser[I, T] {
  Parser::new(input => {
    match self.run(input) {
      Ok((value, rest)) => Ok((value, rest))
      Err(first) =>
        if first.committed {
          Err(first)
        } else {
          other.run(input).map_err(second => first.merge(second))
        }
    }
  })
}

///|
pub fn[I, T] Parser::attempt(self : Parser[I, T]) -> Parser[I, T] {
  Parser::new(input => self.run(input).map_err(error => error.without_commit()))
}

///|
pub fn[I, T] Parser::optional(self : Parser[I, T]) -> Parser[I, T?] {
  Parser::new(input => {
    match self.run(input) {
      Ok((value, rest)) => Ok((Some(value), rest))
      Err(error) => error.reject_if_committed(None, input)
    }
  })
}

///|
pub fn[I : Cursor, T] Parser::many(self : Parser[I, T]) -> Parser[I, Array[T]] {
  Parser::new(input => {
    let values = Array::new()
    for rest = input {
      match self.run(rest) {
        Ok((value, next)) =>
          if next.same_cursor(rest) {
            break Err(
              ParseError::message(rest, "many parser accepted empty input"),
            )
          } else {
            values.push(value)
            continue next
          }
        Err(error) => break error.reject_if_committed(values, rest)
      }
    }
  })
}

///|
pub fn[I : Cursor, T] Parser::some(self : Parser[I, T]) -> Parser[I, Array[T]] {
  self.bind(head => self.many().map(tail => array_cons(tail, head)))
}

///|
pub fn[I : Cursor, T, S] Parser::sep_by(
  self : Parser[I, T],
  sep : Parser[I, S],
) -> Parser[I, Array[T]] {
  self.sep_by1(sep).or(pure([]))
}

///|
pub fn[I : Cursor, T, S] Parser::sep_by1(
  self : Parser[I, T],
  separator : Parser[I, S],
) -> Parser[I, Array[T]] {
  self.bind(head => {
    separator
    .then(self)
    .many()
    .map(tail => {
      let values = Array::new(capacity=tail.length() + 1)
      values.push(head)
      values.append(tail)
      values
    })
  })
}

///|
pub fn[I : Cursor, T] Parser::label(
  self : Parser[I, T],
  expected : String,
) -> Parser[I, T] {
  Parser::new(input => {
    self
    .run(input)
    .map_err(error => {
      guard error.offset == input.cursor() else { error }
      ParseError::new(input, expected)
    })
  })
}

///|
pub fn[T] Parser::lexeme(self : Parser[Input, T]) -> Parser[Input, T] {
  self.skip(spaces())
}

///|
pub fn[I : Cursor, T, L, R] Parser::between(
  self : Parser[I, T],
  left : Parser[I, L],
  right : Parser[I, R],
) -> Parser[I, T] {
  left.then(self).skip(right)
}

///|
pub fn[I : Cursor, T, L] Parser::after(
  self : Parser[I, T],
  left : Parser[I, L],
) -> Parser[I, T] {
  left.then(self)
}

///|
pub fn[I : Cursor, T, R] Parser::before(
  self : Parser[I, T],
  right : Parser[I, R],
) -> Parser[I, T] {
  self.skip(right)
}

///|
pub fn[T] lexeme(parser : Parser[Input, T]) -> Parser[Input, T] {
  parser.lexeme()
}

///|
pub fn symbol(text : String) -> Parser[Input, String] {
  string(text).lexeme()
}

///|
pub fn[I : Cursor, T] Parser::not_followed_by(
  self : Parser[I, T],
  label : String,
) -> Parser[I, Unit] {
  Parser::new(input => {
    match self.run(input) {
      Ok(_) => Err(ParseError::message(input, "unexpected " + label))
      Err(_) => Ok(((), input))
    }
  })
}

///|
pub fn[I : Cursor, T, U] Parser::many_until(
  self : Parser[I, T],
  terminator : Parser[I, U],
) -> Parser[I, Array[T]] {
  Parser::new(input => {
    let values = Array::new()
    for rest = input {
      match terminator.run(rest) {
        Ok((_, next)) => break Ok((values, next))
        Err(_) =>
          match self.run(rest) {
            Ok((value, next)) => {
              if next.same_cursor(rest) {
                break Err(
                  ParseError::message(
                    rest, "many_until parser accepted empty input",
                  ),
                )
              }
              values.push(value)
              continue next
            }
            Err(error) => break error.reject_if_committed(values, rest)
          }
      }
    }
  })
}

///|
fn[I : Cursor, T] choice_impl(
  parsers : Array[Parser[I, T]],
  idx : Int,
  input : I,
) -> Result[(T, I), ParseError] {
  guard idx < parsers.length() else {
    Err(ParseError::message(input, "empty choice"))
  }
  match parsers[idx].run(input) {
    Ok(result) => Ok(result)
    Err(error) => {
      guard !error.committed else { Err(error) }
      choice_impl(parsers, idx + 1, input).map_err(e => error.merge(e))
    }
  }
}

///|
pub fn[I : Cursor, T] choice(parsers : Array[Parser[I, T]]) -> Parser[I, T] {
  Parser::new(input => choice_impl(parsers, 0, input))
}

///|
pub fn[I : Cursor, T, L, R] between(
  left : Parser[I, L],
  parser : Parser[I, T],
  right : Parser[I, R],
) -> Parser[I, T] {
  parser.between(left, right)
}
