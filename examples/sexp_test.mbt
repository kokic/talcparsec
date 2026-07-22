///|
enum Sexp {
  Atom(String)
  Form(Array[Sexp])
} derive(Eq, Debug)

///|
fn atom_parser() -> @talc.StringParser[Sexp] {
  @talc.none_of("() \t\r\n")
  .some()
  .map(chars => Atom(String::from_array(chars)))
  .lexeme()
}

///|
fn sexp_parser() -> @talc.StringParser[Sexp] {
  atom_parser().or(
    @talc.delay(sexp_parser)
    .many()
    .between(@talc.symbol("("), @talc.symbol(")"))
    .map(items => Form(items)),
  )
}

///|
test "parse nested S-expression" {
  let parser = @talc.spaces().then(sexp_parser())
  let result = parser.parse(@talc.Input::new("  (define (square x) (* x x))  "))
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
  @test.assert_eq(parser.parse(@talc.Input::new("()")), Ok(Form([])))
}
