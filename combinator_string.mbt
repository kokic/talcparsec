///|
pub fn[U] Parser::string_map(
  self : Parser[Char],
  f : (String) -> U,
) -> Parser[U] {
  self.bind(value => pure(f(value.to_string())))
}
