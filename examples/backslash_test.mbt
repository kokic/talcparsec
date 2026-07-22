///|
enum TexNode {
  Text(String)
  Command(String, Array[TexNode])
  Group(Array[TexNode])
  InlineMath(Array[TexNode])
  DisplayMath(Array[TexNode])
  OptionalArg(Array[TexNode])
  Superscript(Array[TexNode])
  Subscript(Array[TexNode])
  Comment(String)
  Environment(String, Array[TexNode])
  Verbatim(String)
  Parameter(Int)
} derive(Eq, Debug)

///|
let tex_comment_parser : @talc.StringParser[TexNode] = @talc.char('%')
  .then(@talc.many_chars(@talc.not_newline))
  .map(text => Comment(text))

///|
fn tex_verbatim_parser() -> @talc.StringParser[TexNode] {
  @talc.string("\\verb")
  .attempt()
  .bind(_ => {
    @talc.satisfy("verbatim delimiter", ch => {
      !Char::is_ascii_alphabetic(ch) && ch != '*'
    }).bind(delim => {
      @talc.none_of(delim.to_string())
      .many()
      .map(chars => String::from_array(chars))
      .before(@talc.char(delim))
      .map(content => Verbatim(content))
    })
  })
}

///|
fn tex_math_node_parser() -> @talc.StringParser[TexNode] {
  tex_comment_parser
  .or(tex_verbatim_parser().attempt())
  .or(tex_environment_parser().attempt())
  .or(tex_escaped_special_parser().attempt())
  .or(tex_command_parser())
  .or(tex_parameter_parser())
  .or(tex_group_parser())
  .or(tex_superscript_parser())
  .or(tex_subscript_parser())
  .or(tex_text_parser())
}

///|
fn tex_math_body(closing : String) -> @talc.StringParser[Array[TexNode]] {
  @talc.Parser::new(input => {
    let values = Array::new(capacity=4)
    for current = input {
      match @talc.string(closing).run(current) {
        Ok((_, rest)) => break Ok((values, rest))
        Err(_) =>
          match tex_math_node_parser().run(current) {
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
fn tex_math_parser() -> @talc.StringParser[TexNode] {
  @talc.string("$$")
  .then(tex_math_body("$$"))
  .map(nodes => DisplayMath(nodes))
  .attempt()
  .or(@talc.char('$').then(tex_math_body("$")).map(nodes => InlineMath(nodes)))
}

///|
fn tex_command_name() -> @talc.StringParser[String] {
  @talc.ascii_letter().some().map(chars => String::from_array(chars))
}

///|
fn tex_command_opt_arg() -> @talc.StringParser[Array[TexNode]] {
  @talc.delay(tex_node_parser).many().between(@talc.char('['), @talc.char(']'))
}

///|
fn tex_command_req_arg() -> @talc.StringParser[Array[TexNode]] {
  @talc.delay(tex_node_parser).many().between(@talc.char('{'), @talc.char('}'))
}

///|
fn tex_command_detached_arg() -> @talc.StringParser[TexNode] {
  @talc.satisfy("detached cmd arg", ch => {
    Char::is_ascii_alphabetic(ch) || Char::is_ascii_digit(ch)
  })
  .map(ch => Text(ch.to_string()))
  .or(tex_command_parser())
}

///|
fn tex_cmd_spaces() -> @talc.StringParser[Unit] {
  @talc.space.many().map(_ => ())
}

///|
fn tex_command_args() -> @talc.StringParser[Array[TexNode]] {
  @talc.spaces().then(
    @talc.Parser::new(input => {
      let values = Array::new(capacity=4)
      for current = input {
        if tex_command_opt_arg().run(current) is Ok((nodes, rest)) {
          values.push(OptionalArg(nodes))
          let rest2 = match tex_cmd_spaces().run(rest) {
            Ok((_, r)) => r
            Err(_) => rest
          }
          continue rest2
        }
        if tex_command_req_arg().run(current) is Ok((nodes, rest)) {
          values.append(nodes)
          let rest2 = match tex_cmd_spaces().run(rest) {
            Ok((_, r)) => r
            Err(_) => rest
          }
          continue rest2
        }
        guard tex_command_detached_arg().run(current) is Ok((node, rest)) else {
          break Ok((values, current))
        }
        values.push(node)
        break Ok((values, rest))
      }
    }),
  )
}

///|
fn tex_command_parser() -> @talc.StringParser[TexNode] {
  @talc.char('\\')
  .then(tex_command_name())
  .attempt()
  .bind(name => tex_command_args().map(all => Command(name, all)))
}

///|
fn tex_math_arg() -> @talc.StringParser[Array[TexNode]] {
  @talc.delay(tex_node_parser)
  .many()
  .between(@talc.char('{'), @talc.char('}'))
  .or(
    @talc.satisfy("math token", ch => {
      Char::is_ascii_alphabetic(ch) || Char::is_ascii_digit(ch)
    })
    .map(ch => [Text(ch.to_string())])
    .or(tex_command_parser().map(n => [n])),
  )
}

///|
fn tex_superscript_parser() -> @talc.StringParser[TexNode] {
  @talc.char('^').then(tex_math_arg()).map(nodes => Superscript(nodes))
}

///|
fn tex_subscript_parser() -> @talc.StringParser[TexNode] {
  @talc.char('_').then(tex_math_arg()).map(nodes => Subscript(nodes))
}

///|
fn tex_escaped_special_parser() -> @talc.StringParser[TexNode] {
  @talc.char('\\').then(
    @talc.one_of("\\{}&^_$%#~").map(ch => Text(ch.to_string())),
  )
}

///|
fn tex_env_body(name : String) -> @talc.StringParser[Array[TexNode]] {
  @talc.Parser::new(input => {
    let values = Array::new(capacity=4)
    for current = input {
      match @talc.string("\\end{\{name}}").run(current) {
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
fn tex_environment_parser() -> @talc.StringParser[TexNode] {
  @talc.string("\\begin{")
  .then(tex_command_name())
  .bind(name => {
    @talc.char('}')
    .then(tex_env_body(name))
    .map(nodes => Environment(name, nodes))
  })
}

///|
fn tex_parameter_parser() -> @talc.StringParser[TexNode] {
  @talc.char('#').then(
    @talc.ascii_digit().map(ch => Parameter(ch.to_int() - '0'.to_int())),
  )
}

///|
fn tex_group_parser() -> @talc.StringParser[TexNode] {
  @talc.delay(tex_node_parser)
  .many()
  .between(@talc.char('{'), @talc.char('}'))
  .map(nodes => Group(nodes))
}

///|
fn tex_text_parser() -> @talc.StringParser[TexNode] {
  @talc.take_while("TeX text", ch => {
    ch != '\\' &&
    ch != '{' &&
    ch != '}' &&
    ch != '$' &&
    ch != '%' &&
    ch != '#' &&
    ch != '[' &&
    ch != ']' &&
    ch != '^' &&
    ch != '_'
  }).map(text => Text(text))
}

///|
fn tex_node_parser() -> @talc.StringParser[TexNode] {
  tex_comment_parser
  .or(tex_verbatim_parser().attempt())
  .or(tex_math_parser())
  .or(tex_environment_parser().attempt())
  .or(tex_escaped_special_parser().attempt())
  .or(tex_superscript_parser())
  .or(tex_subscript_parser())
  .or(tex_command_parser())
  .or(tex_parameter_parser())
  .or(tex_group_parser())
  .or(tex_text_parser())
}

///|
fn tex_document_parser() -> @talc.StringParser[Array[TexNode]] {
  @talc.spaces().then(tex_node_parser().many()).skip(@talc.eof())
}

///|
test "parse TeX-like document" {
  let source =
    #|\section{Intro}
    #|Hello \emph{MoonBit}!
    #|
    #|$$ x + \sqrt2 y + \sqrt[3] 3 $$ 
    #|
    #|\{ok\}.
    #|
    #|\begin{center}
    #|  \begin{lemma}
    #|    Hello
    #|  \end{lemma}
    #|\end{center}
  @test.assert_eq(
    tex_document_parser().parse(@talc.Input::new(source)),
    Ok([
      Command("section", [Text("Intro")]),
      Text("\nHello "),
      Command("emph", [Text("MoonBit")]),
      Text("!\n\n"),
      DisplayMath([
        Text(" x + "),
        Command("sqrt", [Text("2")]),
        Text(" y + "),
        Command("sqrt", [OptionalArg([Text("3")]), Text("3")]),
        Text(" "),
      ]),
      Text(" \n\n"),
      Text("{"),
      Text("ok"),
      Text("}"),
      Text(".\n\n"),
      Environment("center", [
        Text("\n  "),
        Environment("lemma", [Text("\n    Hello\n  ")]),
        Text("\n"),
      ]),
    ]),
  )
}

///|
test "parse nested TeX groups and commands" {
  @test.assert_eq(
    tex_document_parser().parse(
      @talc.Input::new("\\textbf{outer {nested} \\emph{inner}}"),
    ),
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
    tex_document_parser().parse(@talc.Input::new("\\LaTeX")),
    Ok([Command("LaTeX", [])]),
  )
}

///|
test "parse display and inline math" {
  @test.assert_eq(
    tex_document_parser().parse(@talc.Input::new("$$\\pi = 3.14$$")),
    Ok([DisplayMath([Command("pi", []), Text("= 3.14")])]),
  )
  @test.assert_eq(
    tex_document_parser().parse(@talc.Input::new("$e^{i\\pi} = -1$")),
    Ok([
      InlineMath([
        Text("e"),
        Superscript([Text("i"), Command("pi", [])]),
        Text(" = -1"),
      ]),
    ]),
  )
}

///|
test "parse TeX comments" {
  @test.assert_eq(
    tex_document_parser().parse(@talc.Input::new("Hello% world\nMoonBit")),
    Ok([Text("Hello"), Comment(" world"), Text("\nMoonBit")]),
  )
  @test.assert_eq(
    tex_document_parser().parse(@talc.Input::new("% full line comment\n\\foo")),
    Ok([Comment(" full line comment"), Text("\n"), Command("foo", [])]),
  )
}

///|
test "parse verbatim text" {
  @test.assert_eq(
    tex_document_parser().parse(@talc.Input::new("\\verb|c@d%$e|")),
    Ok([Verbatim("c@d%$e")]),
  )
  @test.assert_eq(
    tex_document_parser().parse(@talc.Input::new("\\verb+{\\}+")),
    Ok([Verbatim("{\\}")]),
  )
}

///|
test "parse TeX environments" {
  @test.assert_eq(
    tex_document_parser().parse(
      @talc.Input::new("\\begin{center}\nHello\n\\end{center}"),
    ),
    Ok([Environment("center", [Text("\nHello\n")])]),
  )
}

///|
test "parse nested environments" {
  @test.assert_eq(
    tex_document_parser().parse(
      @talc.Input::new("\\begin{outer}\\begin{inner}x\\end{inner}y\\end{outer}"),
    ),
    Ok([Environment("outer", [Environment("inner", [Text("x")]), Text("y")])]),
  )
}

///|
test "parse TeX parameters" {
  @test.assert_eq(
    tex_document_parser().parse(
      @talc.Input::new("\\newcommand{\\foo}[2]{#1 and #2}"),
    ),
    Ok([
      Command("newcommand", [
        Command("foo", []),
        OptionalArg([Text("2")]),
        Parameter(1),
        Text(" and "),
        Parameter(2),
      ]),
    ]),
  )
}

///|
test "parse escaped special characters" {
  @test.assert_eq(
    tex_document_parser().parse(
      @talc.Input::new("\\{ \\} \\\\ \\$ \\& \\# \\% \\_ \\^ \\~"),
    ),
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
    tex_document_parser().parse(@talc.Input::new("\\frac{a}{b}")),
    Ok([Command("frac", [Text("a"), Text("b")])]),
  )
}

///|
test "report unclosed TeX group" {
  match tex_document_parser().parse(@talc.Input::new("\\section{broken")) {
    Err(error) => {
      @test.assert_eq(error.offset(), 15)
      @test.assert_eq(error.line(), 1)
      @test.assert_eq(error.column(), 16)
      @test.assert_eq(error.is_committed(), true)
    }
    Ok(_) => @test.fail("expected an unclosed group error")
  }
}
