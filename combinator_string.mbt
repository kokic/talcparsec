///|
pub type StringParser[T] = Parser[Input, T]

///|
pub fn[U] Parser::string_map(
  self : Parser[Input, Char],
  f : (String) -> U,
) -> Parser[Input, U] {
  self.bind(value => pure(f(value.to_string())))
}
