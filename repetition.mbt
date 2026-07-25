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
              ParseFailure::message(rest, "many parser accepted empty input"),
            )
          } else {
            values.push(value)
            continue next
          }
        Err(error) => break Commit::reject_if_committed(error, values, rest)
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
                  ParseFailure::message(
                    rest, "many_until parser accepted empty input",
                  ),
                )
              }
              values.push(value)
              continue next
            }
            Err(error) => break Commit::reject_if_committed(error, values, rest)
          }
      }
    }
  })
}
