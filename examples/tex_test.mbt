///|
enum TexNode {
  Text(String)
  Command(String, Array[TexNode])
  Group(Array[TexNode])
  InlineMath(String)
} derive(Eq, Debug)

///|
fn tex_group_contents_parser() -> @talcparsec.Parser[Array[TexNode]] {
  @talcparsec.delay(tex_node_parser)
  .many()
  .between(@talcparsec.char('{'), @talcparsec.char('}'))
}

///|
fn tex_command_word_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.ascii_letter()
  .some()
  .map(chars => String::from_array(chars))
  .bind(name => {
    @talcparsec.spaces()
    .then(tex_group_contents_parser().optional())
    .map(argument => Command(name, argument.unwrap_or([])))
  })
}

///|
fn tex_control_parser() -> @talcparsec.Parser[TexNode] {
  let predicate = ch => ['{', '}', '$', '\\'].any(c => c == ch)
  let escaped = @talcparsec.satisfy("escaped TeX special character", predicate)
  let escaped = escaped.string_map(c => Text(c))
  @talcparsec.char('\\').then(escaped.or(tex_command_word_parser()))
}

///|
fn tex_inline_math_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.none_of("$")
  .some()
  .map(chars => String::from_array(chars))
  .between(@talcparsec.char('$'), @talcparsec.char('$'))
  .map(source => InlineMath(source))
}

///|
fn tex_group_parser() -> @talcparsec.Parser[TexNode] {
  tex_group_contents_parser().map(nodes => Group(nodes))
}

///|
fn tex_text_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.take_while("TeX text", ch => {
    ch != '\\' && ch != '{' && ch != '}' && ch != '$'
  }).map(text => Text(text))
}

///|
fn tex_node_parser() -> @talcparsec.Parser[TexNode] {
  tex_control_parser()
  .or(tex_inline_math_parser())
  .or(tex_group_parser())
  .or(tex_text_parser())
}

///|
fn tex_document_parser() -> @talcparsec.Parser[Array[TexNode]] {
  tex_node_parser().many().skip(@talcparsec.eof())
}

///|
test "parse TeX-like document" {
  let source = "\\section{Intro}\nHello \\emph{MoonBit}! $x+y$ \\{ok\\}."
  @test.assert_eq(
    tex_document_parser().parse(source),
    Ok([
      Command("section", [Text("Intro")]),
      Text("\nHello "),
      Command("emph", [Text("MoonBit")]),
      Text("! "),
      InlineMath("x+y"),
      Text(" "),
      Text("{"),
      Text("ok"),
      Text("}"),
      Text("."),
    ]),
  )
}

///|
test "parse nested TeX groups and commands" {
  @test.assert_eq(
    tex_document_parser().parse("\\textbf{outer {nested} \\emph{inner}}"),
    Ok([
      Command("textbf", [
        Text("outer "),
        Group([Text("nested")]),
        Text(" "),
        Command("emph", [Text("inner")]),
      ]),
    ]),
  )
  @test.assert_eq(
    tex_document_parser().parse("\\LaTeX"),
    Ok([Command("LaTeX", [])]),
  )
}

///|
test "report unclosed TeX group" {
  match tex_document_parser().parse("\\section{broken") {
    Err(error) => {
      @test.assert_eq(error.offset(), 15)
      @test.assert_eq(error.line(), 1)
      @test.assert_eq(error.column(), 16)
      @test.assert_eq(error.expected(), ["'}'"])
      @test.assert_eq(error.is_committed(), true)
    }
    Ok(_) => @test.fail("expected an unclosed group error")
  }
}
