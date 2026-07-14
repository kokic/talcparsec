///|
enum Sexp {
  Atom(String)
  Form(Array[Sexp])
} derive(Eq, Debug)

///|
fn atom_parser() -> @talcparsec.Parser[Sexp] {
  @talcparsec.none_of("() \t\r\n")
  .some()
  .map(chars => Atom(String::from_array(chars)))
  .lexeme()
}

///|
fn sexp_parser() -> @talcparsec.Parser[Sexp] {
  atom_parser().or(
    @talcparsec.delay(sexp_parser)
    .many()
    .between(@talcparsec.symbol("("), @talcparsec.symbol(")"))
    .map(items => Form(items)),
  )
}

///|
test "parse nested S-expression" {
  let parser = @talcparsec.spaces().then(sexp_parser())
  let result = parser.parse("  (define (square x) (* x x))  ")
  @test.assert_eq(
    result,
    Ok(
      Form([
        Atom("define"),
        Form([Atom("square"), Atom("x")]),
        Form([Atom("*"), Atom("x"), Atom("x")]),
      ]),
    ),
  )
  @test.assert_eq(parser.parse("()"), Ok(Form([])))
}
