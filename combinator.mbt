///|
/// Core parser combinators: monadic bind, choice, and structural helpers.
///
/// Provides `bind`, `map`, `then`, `skip`, `or`, `attempt`, `optional`,
/// `label`, `lexeme`, `between`, `not_followed_by`, `choice`, and their
/// standalone variants. All combinators respect the commit mechanism for
/// commit-aware backtracking.

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
pub fn[I : Cursor, T, U, E : Commit] ParserRaw::bind(
  self : ParserRaw[I, T, E],
  next : (T) -> ParserRaw[I, U, E],
) -> ParserRaw[I, U, E] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok((value, rest)) =>
        match next(value).run(rest) {
          Ok(result) => Ok(result)
          Err(error) => {
            guard !rest.same_cursor(input) else { Err(error) }
            Err(Commit::mark_committed(error))
          }
        }
      Err(error) => Err(error)
    }
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
pub fn[I, T, U, E] ParserRaw::map(
  self : ParserRaw[I, T, E],
  f : (T) -> U,
) -> ParserRaw[I, U, E] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok((value, rest)) => Ok((f(value), rest))
      Err(error) => Err(error)
    }
  })
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
pub fn[I : Cursor, T, U, E : Commit] ParserRaw::then(
  self : ParserRaw[I, T, E],
  next : ParserRaw[I, U, E],
) -> ParserRaw[I, U, E] {
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
pub fn[I : Cursor, T, U, E : Commit] ParserRaw::skip(
  self : ParserRaw[I, T, E],
  next : ParserRaw[I, U, E],
) -> ParserRaw[I, T, E] {
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
pub fn[I, T, E : Commit + CanMerge] ParserRaw::or(
  self : ParserRaw[I, T, E],
  other : ParserRaw[I, T, E],
) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok((value, rest)) => Ok((value, rest))
      Err(first) if Commit::is_committed(first) => Err(first)
      Err(first) =>
        other.run(input).map_err(second => CanMerge::merge(first, second))
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
pub fn[I, T, E : Commit] ParserRaw::attempt(
  self : ParserRaw[I, T, E],
) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => {
    self.run(input).map_err(error => Commit::clear_commit(error))
  })
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
pub fn[I, T, E : Commit] ParserRaw::optional(
  self : ParserRaw[I, T, E],
) -> ParserRaw[I, T?, E] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok((value, rest)) => Ok((Some(value), rest))
      Err(error) => Commit::reject_if_committed(error, None, input)
    }
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
/// is preserved (furthest position wins). A replaced label
/// keeps the original error's committed flag.
pub fn[I : Cursor, T, E : ParseFailure] ParserRaw::label(
  self : ParserRaw[I, T, E],
  expected : String,
) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => {
    self
    .run(input)
    .map_err(error => {
      guard Positioned::error_offset(error) == input.cursor() else { error }
      let labeled = ParseFailure::signal(input, expected)
      guard Commit::is_committed(error) else { labeled }
      Commit::mark_committed(labeled)
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
/// Returns a parser that runs `self` then skips whitespace.
#inline
pub fn[T] ParserRaw::lexeme(self : Parser[Input, T]) -> Parser[Input, T] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok((value, rest)) => Ok((value, skip_ws(rest)))
      Err(error) => Err(error)
    }
  })
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
pub fn[I : Cursor, T, L, R, E : Commit] ParserRaw::between(
  self : ParserRaw[I, T, E],
  left : ParserRaw[I, L, E],
  right : ParserRaw[I, R, E],
) -> ParserRaw[I, T, E] {
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
pub fn[I : Cursor, T, L, E : Commit] ParserRaw::after(
  self : ParserRaw[I, T, E],
  left : ParserRaw[I, L, E],
) -> ParserRaw[I, T, E] {
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
pub fn[I : Cursor, T, R, E : Commit] ParserRaw::before(
  self : ParserRaw[I, T, E],
  right : ParserRaw[I, R, E],
) -> ParserRaw[I, T, E] {
  self.skip(right)
}

///|
/// Standalone version of `Parser::lexeme`.
#inline
pub fn[T] lexeme(parser : Parser[Input, T]) -> Parser[Input, T] {
  parser.lexeme()
}

///|
/// Matches an exact string, then skips trailing whitespace.
#inline
pub fn symbol(text : String) -> Parser[Input, String] {
  string(text).lexeme()
}

///|
/// Negative lookahead. Succeeds with `()` (consuming no input)
/// when `self` fails.
#inline
pub fn[I : Cursor, T, E : ParseFailure] ParserRaw::not_followed_by(
  self : ParserRaw[I, T, E],
  label : String,
) -> ParserRaw[I, Unit, E] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok(_) => Err(ParseFailure::message(input, "unexpected \{label}"))
      Err(_) => Ok(((), input))
    }
  })
}

///|
/// Tries each parser in the array in order on the same input.
///
/// Iterates through parsers, accumulating errors via `CanMerge::merge`.
/// On committed failure, propagation is immediate — no further alternatives
/// are tried. If no parser succeeds, the merged error (or a fallback message
/// for an empty array) is returned.
#inline
pub fn[I : Cursor, T, E : Commit + CanMerge + ParseFailure] choice(
  parsers : Array[ParserRaw[I, T, E]],
) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => {
    let mut merged : E? = None
    for i = 0; i < parsers.length(); i = i + 1 {
      match parsers[i].run(input) {
        Ok(result) => break Ok(result)
        Err(error) => {
          guard !Commit::is_committed(error) else { break Err(error) }
          // Accumulate: merge the latest error into the running combination.
          merged = match merged {
            Some(prev) => Some(CanMerge::merge(prev, error))
            None => Some(error)
          }
          continue
        }
      }
    } nobreak {
      match merged {
        Some(err) => Err(err)
        None => Err(ParseFailure::message(input, "empty choice"))
      }
    }
  })
}

///|
/// Standalone version of `Parser::between`.
#inline
pub fn[I : Cursor, T, L, R, E : Commit] between(
  left : ParserRaw[I, L, E],
  parser : ParserRaw[I, T, E],
  right : ParserRaw[I, R, E],
) -> ParserRaw[I, T, E] {
  parser.between(left, right)
}
