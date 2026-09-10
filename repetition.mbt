///|
/// Repetition combinators: many, some, and separated variants.
///
/// Provides `many`, `some`, `sep_by`, `sep_by1`, and `many_until`.
/// All repetition parsers guard against infinite loops by checking for
/// zero-length progress via `same_cursor`.

///|
/// Zero or more repetitions of `self`.
///
/// Stops on non-committed failure. Rejects parsers that accept
/// empty input (infinite loop guard).
pub fn[I : Cursor, T, E : Commit + ParseFailure] ParserRaw::many(
  self : ParserRaw[I, T, E],
) -> ParserRaw[I, Array[T], E] {
  ParserRaw::new(input => {
    let values = Array()
    for rest = input {
      match self.run(rest) {
        Ok((value, next)) => {
          guard !next.same_cursor(rest) else {
            break Err(
              ParseFailure::message(rest, "many parser accepted empty input"),
            )
          }
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
#inline
pub fn[I : Cursor, T, E : Commit + ParseFailure] ParserRaw::some(
  self : ParserRaw[I, T, E],
) -> ParserRaw[I, Array[T], E] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok((head, rest)) => {
        let values = Array()
        values.push(head)
        for r = rest {
          match self.run(r) {
            Ok((value, next)) => {
              guard !next.same_cursor(r) else {
                break Err(
                  ParseFailure::message(r, "many parser accepted empty input"),
                )
              }
              values.push(value)
              continue next
            }
            Err(error) => break Commit::reject_if_committed(error, values, r)
          }
        }
      }
      Err(error) => Err(error)
    }
  })
}

///|
/// Zero or more repetitions of `self` separated by `sep`.
#inline
pub fn[I : Cursor, T, S, E : Commit + CanMerge + ParseFailure] ParserRaw::sep_by(
  self : ParserRaw[I, T, E],
  sep : ParserRaw[I, S, E],
) -> ParserRaw[I, Array[T], E] {
  self.sep_by1(sep).or(pure([]))
}

///|
/// One or more repetitions of `self` separated by `separator`.
pub fn[I : Cursor, T, S, E : Commit + ParseFailure] ParserRaw::sep_by1(
  self : ParserRaw[I, T, E],
  separator : ParserRaw[I, S, E],
) -> ParserRaw[I, Array[T], E] {
  ParserRaw::new(input => {
    match self.run(input) {
      Ok((head, rest)) => {
        let values = Array()
        values.push(head)
        for r = rest {
          match separator.run(r) {
            Ok((_, after_sep)) =>
              match self.run(after_sep) {
                Ok((value, next)) => {
                  guard !next.same_cursor(r) else {
                    break Err(
                      ParseFailure::message(
                        r, "many parser accepted empty input",
                      ),
                    )
                  }
                  values.push(value)
                  continue next
                }
                Err(error) => {
                  guard after_sep.same_cursor(r) else {
                    break Err(Commit::mark_committed(error))
                  }
                  break Commit::reject_if_committed(error, values, r)
                }
              }
            Err(error) => break Commit::reject_if_committed(error, values, r)
          }
        }
      }
      Err(error) => Err(error)
    }
  })
}

///|
/// Keeps running `self` until `terminator` succeeds.
pub fn[I : Cursor, T, U, E : Commit + ParseFailure] ParserRaw::many_until(
  self : ParserRaw[I, T, E],
  terminator : ParserRaw[I, U, E],
) -> ParserRaw[I, Array[T], E] {
  ParserRaw::new(input => {
    let values = Array()
    for rest = input {
      match terminator.run(rest) {
        Ok((_, next)) => break Ok((values, next))
        Err(_) =>
          match self.run(rest) {
            Ok((value, next)) => {
              guard !next.same_cursor(rest) else {
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
