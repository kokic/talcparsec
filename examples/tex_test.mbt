///|
enum TexNode {
  Text(String)
  Command(String, Array[TexNode])
  Group(Array[TexNode])
  InlineMath(String)
  DisplayMath(String)
  Comment(String)
  Environment(String, Array[TexNode])
  Verbatim(String)
  Parameter(Int)
} derive(Eq, Debug)

///|
fn tex_comment_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.char('%')
  .then(
    @talcparsec.none_of("\n").many().map(chars => String::from_array(chars)),
  )
  .map(text => Comment(text))
}

///|
fn tex_verbatim_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.string("\\verb")
  .attempt()
  .bind(_ => {
    @talcparsec.satisfy("verbatim delimiter", ch => {
      !Char::is_ascii_alphabetic(ch) && ch != '*'
    }).bind(delim => {
      @talcparsec.none_of(delim.to_string())
      .many()
      .map(chars => String::from_array(chars))
      .before(@talcparsec.char(delim))
      .map(content => Verbatim(content))
    })
  })
}

///|
fn tex_math_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.string("$$")
  .then(@talcparsec.none_of("$").many().map(chars => String::from_array(chars)))
  .before(@talcparsec.string("$$"))
  .map(content => DisplayMath(content))
  .attempt()
  .or(
    @talcparsec.char('$')
    .then(
      @talcparsec.none_of("$").many().map(chars => String::from_array(chars)),
    )
    .before(@talcparsec.char('$'))
    .map(content => InlineMath(content)),
  )
}

///|
fn tex_command_name() -> @talcparsec.Parser[String] {
  @talcparsec.ascii_letter().some().map(chars => String::from_array(chars))
}

///|
fn tex_command_arg() -> @talcparsec.Parser[Array[TexNode]] {
  @talcparsec.delay(tex_node_parser)
  .many()
  .between(@talcparsec.char('{'), @talcparsec.char('}'))
}

///|
fn tex_command_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.char('\\')
  .then(tex_command_name())
  .attempt()
  .bind(name => {
    @talcparsec.spaces()
    .then(tex_command_arg().many())
    .map(args => {
      let values = Array::new(capacity=args.length() * 4)
      for arg in args {
        values.append(arg)
      }
      Command(name, values)
    })
  })
}

///|
fn tex_escaped_special_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.char('\\').then(
    @talcparsec.one_of("\\{}&^_$%#~").map(ch => Text(ch.to_string())),
  )
}

///|
fn tex_env_body(name : String) -> @talcparsec.Parser[Array[TexNode]] {
  @talcparsec.Parser::new(input => {
    let values = Array::new(capacity=4)
    for current = input {
      match @talcparsec.string("\\end{" + name + "}").run(current) {
        Ok((_, rest)) => break Ok((values, rest))
        Err(_) =>
          match tex_node_parser().run(current) {
            Ok((node, rest)) => {
              values.push(node)
              continue rest
            }
            Err(error) => break Err(error)
          }
      }
    }
  })
}

///|
fn tex_environment_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.string("\\begin{")
  .then(tex_command_name())
  .bind(name => {
    @talcparsec.char('}')
    .then(tex_env_body(name))
    .map(nodes => Environment(name, nodes))
  })
}

///|
fn tex_parameter_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.char('#').then(
    @talcparsec.ascii_digit().map(ch => Parameter(ch.to_int() - '0'.to_int())),
  )
}

///|
fn tex_group_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.delay(tex_node_parser)
  .many()
  .between(@talcparsec.char('{'), @talcparsec.char('}'))
  .map(nodes => Group(nodes))
}

///|
fn tex_text_parser() -> @talcparsec.Parser[TexNode] {
  @talcparsec.take_while("TeX text", ch => {
    ch != '\\' && ch != '{' && ch != '}' && ch != '$' && ch != '%' && ch != '#'
  }).map(text => Text(text))
}

///|
fn tex_node_parser() -> @talcparsec.Parser[TexNode] {
  tex_comment_parser()
  .or(tex_verbatim_parser().attempt())
  .or(tex_math_parser())
  .or(tex_environment_parser().attempt())
  .or(tex_escaped_special_parser().attempt())
  .or(tex_command_parser())
  .or(tex_parameter_parser())
  .or(tex_group_parser())
  .or(tex_text_parser())
}

///|
fn tex_document_parser() -> @talcparsec.Parser[Array[TexNode]] {
  @talcparsec.spaces().then(tex_node_parser().many()).skip(@talcparsec.eof())
}

///|
test "parse TeX-like document" {
  let source =
    #|\section{Intro}
    #|Hello \emph{MoonBit}!
    #|
    #|$$ x+y $$ 
    #|
    #|\{ok\}.
  debug_inspect(tex_document_parser().parse(source), content=(
    #|Ok(
    #|  [
    #|    Command("section", [Text("Intro")]),
    #|    Text("\nHello "),
    #|    Command("emph", [Text("MoonBit")]),
    #|    Text("!\n\n"),
    #|    DisplayMath(" x+y "),
    #|    Text(" \n\n"),
    #|    Text("{"),
    #|    Text("ok"),
    #|    Text("}"),
    #|    Text("."),
    #|  ],
    #|)
  ))
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
test "parse display and inline math" {
  @test.assert_eq(
    tex_document_parser().parse("$$\\pi = 3.14$$"),
    Ok([DisplayMath("\\pi = 3.14")]),
  )
  @test.assert_eq(
    tex_document_parser().parse("$e^{i\\pi} = -1$"),
    Ok([InlineMath("e^{i\\pi} = -1")]),
  )
}

///|
test "parse TeX comments" {
  @test.assert_eq(
    tex_document_parser().parse("Hello% world\nMoonBit"),
    Ok([Text("Hello"), Comment(" world"), Text("\nMoonBit")]),
  )
  @test.assert_eq(
    tex_document_parser().parse("% full line comment\n\\foo"),
    Ok([Comment(" full line comment"), Text("\n"), Command("foo", [])]),
  )
}

///|
test "parse verbatim text" {
  @test.assert_eq(
    tex_document_parser().parse("\\verb|c@d%$e|"),
    Ok([Verbatim("c@d%$e")]),
  )
  @test.assert_eq(
    tex_document_parser().parse("\\verb+{\\}+"),
    Ok([Verbatim("{\\}")]),
  )
}

///|
test "parse TeX environments" {
  @test.assert_eq(
    tex_document_parser().parse("\\begin{center}\nHello\n\\end{center}"),
    Ok([Environment("center", [Text("\nHello\n")])]),
  )
}

///|
test "parse nested environments" {
  @test.assert_eq(
    tex_document_parser().parse(
      "\\begin{outer}\\begin{inner}x\\end{inner}y\\end{outer}",
    ),
    Ok([Environment("outer", [Environment("inner", [Text("x")]), Text("y")])]),
  )
}

///|
test "parse TeX parameters" {
  @test.assert_eq(
    tex_document_parser().parse("\\newcommand{\\foo}[2]{#1 and #2}"),
    Ok([
      Command("newcommand", [Command("foo", [])]),
      Text("[2]"),
      Group([Parameter(1), Text(" and "), Parameter(2)]),
    ]),
  )
}

///|
test "parse escaped special characters" {
  @test.assert_eq(
    tex_document_parser().parse("\\{ \\} \\\\ \\$ \\& \\# \\% \\_ \\^ \\~"),
    Ok([
      Text("{"),
      Text(" "),
      Text("}"),
      Text(" "),
      Text("\\"),
      Text(" "),
      Text("$"),
      Text(" "),
      Text("&"),
      Text(" "),
      Text("#"),
      Text(" "),
      Text("%"),
      Text(" "),
      Text("_"),
      Text(" "),
      Text("^"),
      Text(" "),
      Text("~"),
    ]),
  )
}

///|
test "parse command with multiple arguments" {
  @test.assert_eq(
    tex_document_parser().parse("\\frac{a}{b}"),
    Ok([Command("frac", [Text("a"), Text("b")])]),
  )
}

///|
test "report unclosed TeX group" {
  match tex_document_parser().parse("\\section{broken") {
    Err(error) => {
      @test.assert_eq(error.offset(), 15)
      @test.assert_eq(error.line(), 1)
      @test.assert_eq(error.column(), 16)
      @test.assert_eq(error.is_committed(), true)
    }
    Ok(_) => @test.fail("expected an unclosed group error")
  }
}
