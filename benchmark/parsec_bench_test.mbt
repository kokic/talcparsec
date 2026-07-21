///|
enum Sexp {
  Atom(String)
  Form(Array[Sexp])
}

///|
fn Sexp::node_count(self : Sexp) -> Int {
  match self {
    Atom(text) => if text.is_empty() { 0 } else { 1 }
    Form(items) =>
      items.fold(init=1, (count, item) => count + item.node_count())
  }
}

///|
fn repeat_text(text : String, count : Int) -> String {
  let buffer = StringBuilder(size_hint=text.length() * count)
  for _ in 0..<count {
    buffer.write_string(text)
  }
  buffer.to_string()
}

///|
fn make_identifier_list(count : Int) -> String {
  let buffer = StringBuilder(size_hint=count * 7)
  for i in 0..<count {
    if i > 0 {
      buffer.write_char(',')
      buffer.write_char(' ')
    }
    buffer.write_string("alpha")
  }
  buffer.to_string()
}

///|
fn make_flat_sexp(count : Int) -> String {
  let buffer = StringBuilder(size_hint=count * 6 + 2)
  buffer.write_char('(')
  for i in 0..<count {
    if i > 0 {
      buffer.write_char(' ')
    }
    buffer.write_string("alpha")
  }
  buffer.write_char(')')
  buffer.to_string()
}

///|
fn make_nested_sexp(depth : Int) -> String {
  repeat_text("(", depth) + "alpha" + repeat_text(")", depth)
}

///|
fn identifier_parser() -> @talcparsec.StringParser[String] {
  @talcparsec.ascii_letter()
  .some()
  .map(chars => String::from_array(chars))
  .lexeme()
}

///|
fn atom_parser() -> @talcparsec.StringParser[Sexp] {
  @talcparsec.none_of("() \t\r\n")
  .some()
  .map(chars => Atom(String::from_array(chars)))
  .lexeme()
}

///|
fn sexp_parser() -> @talcparsec.StringParser[Sexp] {
  atom_parser().or(
    @talcparsec.delay(sexp_parser)
    .many()
    .between(@talcparsec.symbol("("), @talcparsec.symbol(")"))
    .map(items => Form(items)),
  )
}

///|
fn character_choice(chars : String) -> @talcparsec.StringParser[Char] {
  let mut parser : @talcparsec.StringParser[Char]? = None
  for ch in chars {
    parser = Some(
      match parser {
        None => @talcparsec.char(ch)
        Some(current) => current.or(@talcparsec.char(ch))
      },
    )
  }
  match parser {
    Some(parser) => parser
    None => @talcparsec.fail("character")
  }
}

///|
test "bench string exact n=4096" (it : @bench.T) {
  let input = repeat_text("a", 4096)
  let parser = @talcparsec.string(input)
  it.bench(() => it.keep(parser.parse(@talcparsec.Input::new(input))))
}

///|
test "bench take_while ASCII n=4096" (it : @bench.T) {
  let input = repeat_text("a", 4096)
  let parser = @talcparsec.take_while(
    "ASCII letters",
    Char::is_ascii_alphabetic,
  )
  it.bench(() => it.keep(parser.parse(@talcparsec.Input::new(input))))
}

///|
test "bench sep_by identifiers n=1000" (it : @bench.T) {
  let input = make_identifier_list(1000)
  let parser = identifier_parser().sep_by(@talcparsec.symbol(","))
  it.bench(() => it.keep(parser.parse(@talcparsec.Input::new(input))))
}

///|
test "bench S-expression flat atoms n=1000" (it : @bench.T) {
  let input = make_flat_sexp(1000)
  let parser = @talcparsec.spaces().then(sexp_parser())
  match parser.parse(@talcparsec.Input::new(input)) {
    Ok(value) => it.keep(value.node_count())
    Err(error) => it.keep(error.offset())
  }
  it.bench(() => it.keep(parser.parse(@talcparsec.Input::new(input))))
}

///|
test "bench S-expression nested depth=128" (it : @bench.T) {
  let input = make_nested_sexp(128)
  let parser = sexp_parser()
  it.bench(() => it.keep(parser.parse(@talcparsec.Input::new(input))))
}

///|
test "bench attempt common prefix n=4096" (it : @bench.T) {
  let prefix = repeat_text("a", 4096)
  let input = prefix + "c"
  let parser = @talcparsec.string(prefix + "b")
    .attempt()
    .or(@talcparsec.string(input))
  it.bench(() => it.keep(parser.parse(@talcparsec.Input::new(input))))
}

///|
test "bench choice failure alternatives=26" (it : @bench.T) {
  let parser = character_choice("abcdefghijklmnopqrstuvwxyz")
  it.bench(() => it.keep(parser.parse(@talcparsec.Input::new("!"))))
}
