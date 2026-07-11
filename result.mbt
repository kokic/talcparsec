///|
pub(all) enum ParseResult[T] {
  Ok(T, Input)
  Err(ParseError)
} derive(Eq, Debug)

///|
pub fn[T] ParseResult::is_ok(self : ParseResult[T]) -> Bool {
  self is Ok(_)
}

///|
pub fn[T] ParseResult::unwrap(self : ParseResult[T]) -> (T, Input) {
  match self {
    Ok(value, input) => (value, input)
    Err(error) => abort(error.to_string())
  }
}
