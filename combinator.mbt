///|
/// Monadic bind. Runs `self`, passes the result to `next`.
///
/// Parameters:
///
/// * `self` : The first parser to run.
/// * `next` : A function that takes the result of `self` and returns
///   the next parser to run.
///
/// If `self` consumed input, any error from `next` is marked committed,
/// preventing backtracking across consumed input.
///
/// Returns a parser that runs `self`, then feeds its result to `next`.
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
/// Transforms the result of a successful parse using `f`.
///
/// Parameters:
///
/// * `self` : The parser whose result to transform.
/// * `f` : The transformation function.
///
/// Returns a parser that parses the same input as `self`
/// and applies `f` to the result on success.
#inline
pub fn[I : Cursor, T, U] Parser::map(
  self : Parser[I, T],
  f : (T) -> U,
) -> Parser[I, U] {
  self.bind(value => pure(f(value)))
}

///|
/// Runs `self` then `next`, discarding `self`'s result.
///
/// Parameters:
///
/// * `self` : The first parser; its result is discarded.
/// * `next` : The second parser; its result is returned.
///
/// Equivalent to `self >> next`.
#inline
pub fn[I : Cursor, T, U] Parser::then(
  self : Parser[I, T],
  next : Parser[I, U],
) -> Parser[I, U] {
  self.bind(_ => next)
}

///|
/// Runs `self` then `next`, returning `self`'s result.
///
/// Parameters:
///
/// * `self` : The first parser; its result is returned.
/// * `next` : The second parser; its result is discarded.
///
/// Equivalent to `self <* next`.
#inline
pub fn[I : Cursor, T, U] Parser::skip(
  self : Parser[I, T],
  next : Parser[I, U],
) -> Parser[I, T] {
  self.bind(value => next.map(_ => value))
}

///|
/// Choice with commit-aware backtracking.
///
/// Parameters:
///
/// * `self` : The first alternative.
/// * `other` : The second alternative, tried if `self` fails
///   without committing.
///
/// If `self` fails with committed error, `other` is NOT tried.
/// Errors are merged by furthest position.
///
/// Returns the result of the first successful alternative.
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
/// Strips the committed flag from any error.
///
/// Parameters:
///
/// * `self` : The parser to wrap.
///
/// Enables backtracking across input consumed by `self`.
/// Use sparingly — prefer grammars where alternatives are
/// distinguishable without backtracking.
#inline
pub fn[I, T] Parser::attempt(self : Parser[I, T]) -> Parser[I, T] {
  Parser::new(input => self.run(input).map_err(error => error.without_commit()))
}

///|
/// Runs `self` and returns `Some(result)` on success.
///
/// Parameters:
///
/// * `self` : The parser to try.
///
/// Returns `None` on non-committed failure. Committed failures
/// propagate immediately.
pub fn[I, T] Parser::optional(self : Parser[I, T]) -> Parser[I, T?] {
  Parser::new(input => {
    match self.run(input) {
      Ok((value, rest)) => Ok((Some(value), rest))
      Err(error) => error.reject_if_committed(None, input)
    }
  })
}

///|
/// Zero or more repetitions of `self`.
///
/// Parameters:
///
/// * `self` : The parser to repeat.
///
/// Stops on non-committed failure. Rejects parsers that accept
/// empty input (infinite loop guard).
///
/// Returns an array of accumulated results.
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
/// One or more repetitions of `self`.
///
/// Parameters:
///
/// * `self` : The parser to repeat. Must match at least once.
///
/// Implemented as `self` followed by `self.many()`.
///
/// Returns an array of accumulated results.
#inline
pub fn[I : Cursor, T] Parser::some(self : Parser[I, T]) -> Parser[I, Array[T]] {
  self.bind(head => self.many().map(tail => array_cons(tail, head)))
}

///|
/// Zero or more repetitions of `self` separated by `sep`.
///
/// Parameters:
///
/// * `self` : The value parser.
/// * `sep` : The separator parser; its result is discarded.
///
/// Returns empty array on no match.
#inline
pub fn[I : Cursor, T, S] Parser::sep_by(
  self : Parser[I, T],
  sep : Parser[I, S],
) -> Parser[I, Array[T]] {
  self.sep_by1(sep).or(pure([]))
}

///|
/// One or more repetitions of `self` separated by `separator`.
///
/// Parameters:
///
/// * `self` : The value parser.
/// * `separator` : The separator parser; its result is discarded.
///
/// Requires at least one match of `self`.
///
/// Returns an array of value results.
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
/// Replaces the expected label in the error if `self` fails
/// without having advanced the cursor.
///
/// Parameters:
///
/// * `self` : The parser to label.
/// * `expected` : The label to report on failure.
///
/// If input was consumed before failure, the original error
/// is preserved (furthest position wins).
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
/// Wraps `self` as a lexeme by skipping trailing whitespace.
///
/// Parameters:
///
/// * `self` : The parser to wrap.
///
/// Only valid for `Input`-based parsers.
///
/// Returns a parser that runs `self` then skips whitespace.
#inline
pub fn[T] Parser::lexeme(self : Parser[Input, T]) -> Parser[Input, T] {
  self.skip(spaces())
}

///|
/// Runs `left`, then `self`, then `right`, returning `self`'s result.
///
/// Parameters:
///
/// * `self` : The middle parser whose result is returned.
/// * `left` : The opening parser; its result is discarded.
/// * `right` : The closing parser; its result is discarded.
///
/// Equivalent to `left.then(self).skip(right)`.
#inline
pub fn[I : Cursor, T, L, R] Parser::between(
  self : Parser[I, T],
  left : Parser[I, L],
  right : Parser[I, R],
) -> Parser[I, T] {
  left.then(self).skip(right)
}

///|
/// Runs `left` then `self`, returning `self`'s result.
///
/// Parameters:
///
/// * `self` : The parser whose result is returned.
/// * `left` : The parser whose result is discarded.
///
/// Equivalent to `left *> self`.
#inline
pub fn[I : Cursor, T, L] Parser::after(
  self : Parser[I, T],
  left : Parser[I, L],
) -> Parser[I, T] {
  left.then(self)
}

///|
/// Runs `self` then `right`, returning `self`'s result.
///
/// Parameters:
///
/// * `self` : The parser whose result is returned.
/// * `right` : The parser whose result is discarded.
///
/// Equivalent to `self <* right`.
#inline
pub fn[I : Cursor, T, R] Parser::before(
  self : Parser[I, T],
  right : Parser[I, R],
) -> Parser[I, T] {
  self.skip(right)
}

///|
/// Standalone version of `Parser::lexeme`.
///
/// Parameters:
///
/// * `parser` : The parser to wrap.
///
/// Returns a parser that runs `parser` then skips trailing whitespace.
#inline
pub fn[T] lexeme(parser : Parser[Input, T]) -> Parser[Input, T] {
  parser.lexeme()
}

///|
/// Matches an exact string, then skips trailing whitespace.
///
/// Parameters:
///
/// * `text` : The string to match.
///
/// Returns a parser that matches `text` followed by optional whitespace.
#inline
pub fn symbol(text : String) -> Parser[Input, String] {
  string(text).lexeme()
}

///|
/// Negative lookahead. Succeeds with `()` (consuming no input)
/// when `self` fails.
///
/// Parameters:
///
/// * `self` : The parser to check for absence.
/// * `label` : The label for error messages when `self` succeeds.
///
/// When `self` succeeds, fails with an uncommitted error
/// `"unexpected {label}"`.
#inline
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
/// Keeps running `self` until `terminator` succeeds.
///
/// Parameters:
///
/// * `self` : The body parser to repeat.
/// * `terminator` : The terminator parser. It is consumed but
///   its result is not included in the output.
///
/// If `self` fails with a non-committed error, accumulated values
/// are returned. Committed errors from `self` propagate immediately.
///
/// Returns an array of results from `self`.
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
/// Tries each parser in the array in order on the same input.
///
/// Parameters:
///
/// * `parsers` : The array of alternative parsers.
///
/// Returns the first success. Merges errors from all failures
/// (furthest position wins). Aborts immediately on committed errors.
#inline
pub fn[I : Cursor, T] choice(parsers : Array[Parser[I, T]]) -> Parser[I, T] {
  Parser::new(input => choice_impl(parsers, 0, input))
}

///|
/// Standalone version of `Parser::between`.
///
/// Parameters:
///
/// * `left` : The opening parser; its result is discarded.
/// * `parser` : The middle parser whose result is returned.
/// * `right` : The closing parser; its result is discarded.
#inline
pub fn[I : Cursor, T, L, R] between(
  left : Parser[I, L],
  parser : Parser[I, T],
  right : Parser[I, R],
) -> Parser[I, T] {
  parser.between(left, right)
}
