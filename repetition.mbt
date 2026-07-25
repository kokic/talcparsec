///|
/// Zero or more repetitions of `self`.
///
/// Stops on non-committed failure. Rejects parsers that accept
/// empty input (infinite loop guard).
pub fn[I : Cursor, T, E : Commit + ParseFailure] ParserRaw::many(
  self : ParserRaw[I, T, E],
) -> ParserRaw[I, Array[T], E] {
  ParserRaw::new(input => {
    let values = Array::new()
    for rest = input {
      match self.run(rest) {
        Ok((value, next)) =>
          if next.same_cursor(rest) {
            break Err(
              ParseFailure::message(
                rest, "many parser accepted empty input",
              ),
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
#inline
pub fn[I : Cursor, T, E : Commit + ParseFailure] ParserRaw::some(
  self : ParserRaw[I, T, E],
) -> ParserRaw[I, Array[T], E] {
  self.bind(head => self.many().map(tail => array_cons(tail, head)))
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
pub fn[I : Cursor, T, U, E : Commit + ParseFailure] ParserRaw::many_until(
  self : ParserRaw[I, T, E],
  terminator : ParserRaw[I, U, E],
) -> ParserRaw[I, Array[T], E] {
  ParserRaw::new(input => {
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
