///|
pub fn[T, U] Parser::bind(
  self : Parser[T],
  next : (T) -> Parser[U],
) -> Parser[U] {
  Parser::new(input => {
    match self.run(input) {
      Ok(value, rest) =>
        match next(value).run(rest) {
          Ok(out, end) => Ok(out, end)
          Err(error) =>
            Err(
              if rest.offset != input.offset {
                error.with_commit()
              } else {
                error
              },
            )
        }
      Err(error) => Err(error)
    }
  })
}

///|
pub fn[T, U] Parser::map(self : Parser[T], f : (T) -> U) -> Parser[U] {
  self.bind(value => pure(f(value)))
}

///|
pub fn[T, U] Parser::then(self : Parser[T], next : Parser[U]) -> Parser[U] {
  self.bind(_ => next)
}

///|
pub fn[T, U] Parser::skip(self : Parser[T], next : Parser[U]) -> Parser[T] {
  self.bind(value => next.map(_ => value))
}

///|
pub fn[T] Parser::or(self : Parser[T], other : Parser[T]) -> Parser[T] {
  Parser::new(input => {
    match self.run(input) {
      Ok(value, rest) => Ok(value, rest)
      Err(first) =>
        if first.committed {
          Err(first)
        } else {
          match other.run(input) {
            Ok(value, rest) => Ok(value, rest)
            Err(second) => Err(first.merge(second))
          }
        }
    }
  })
}

///|
pub fn[T] Parser::attempt(self : Parser[T]) -> Parser[T] {
  Parser::new(input => {
    match self.run(input) {
      Ok(value, rest) => Ok(value, rest)
      Err(error) => Err(error.without_commit())
    }
  })
}

///|
pub fn[T] Parser::optional(self : Parser[T]) -> Parser[T?] {
  Parser::new(input => {
    match self.run(input) {
      Ok(value, rest) => Ok(Some(value), rest)
      Err(error) => error.reject_if_committed(None, input)
    }
  })
}

///|
pub fn[T] Parser::many(self : Parser[T]) -> Parser[Array[T]] {
  Parser::new(input => {
    let values = Array::new()
    for rest = input {
      match self.run(rest) {
        Ok(value, next) =>
          if next.offset == rest.offset {
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
pub fn[T] Parser::some(self : Parser[T]) -> Parser[Array[T]] {
  self.bind(head => self.many().map(tail => array_cons(tail, head)))
}

///|
pub fn[T, S] Parser::sep_by(
  self : Parser[T],
  sep : Parser[S],
) -> Parser[Array[T]] {
  self.sep_by1(sep).or(pure([]))
}

///|
pub fn[T, S] Parser::sep_by1(
  self : Parser[T],
  sep : Parser[S],
) -> Parser[Array[T]] {
  self.bind(head => {
    sep
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
pub fn[T] Parser::label(self : Parser[T], expected : String) -> Parser[T] {
  Parser::new(input => {
    match self.run(input) {
      Ok(value, rest) => Ok(value, rest)
      Err(error) =>
        if error.offset == input.offset {
          Err(ParseError::new(input, expected))
        } else {
          Err(error)
        }
    }
  })
}

///|
pub fn[T] Parser::lexeme(self : Parser[T]) -> Parser[T] {
  self.skip(spaces())
}

///|
pub fn[T, L, R] Parser::between(
  self : Parser[T],
  left : Parser[L],
  right : Parser[R],
) -> Parser[T] {
  left.then(self).skip(right)
}

///|
pub fn[T, L] Parser::after(self : Parser[T], left : Parser[L]) -> Parser[T] {
  left.then(self)
}

///|
pub fn[T, R] Parser::before(self : Parser[T], right : Parser[R]) -> Parser[T] {
  self.skip(right)
}

///|
pub fn[T] lexeme(parser : Parser[T]) -> Parser[T] {
  parser.lexeme()
}

///|
pub fn symbol(text : String) -> Parser[String] {
  string(text).lexeme()
}

///|
pub fn[T, L, R] between(
  left : Parser[L],
  parser : Parser[T],
  right : Parser[R],
) -> Parser[T] {
  parser.between(left, right)
}
