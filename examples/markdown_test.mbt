///|
/// AST types
enum Inline {
  Plain(String)
  Strong(Array[Inline])
  Emph(Array[Inline])
  Code(String)
  Link(Array[Inline], String)
  Image(String, String)
} derive(Eq, Debug)

///|
enum Block {
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  Blockquote(Array[Block])
  UnorderedList(Array[MdListItem])
  OrderedList(Array[MdListItem])
  FencedCode(String?, String)
  ThematicBreak
} derive(Eq, Debug)

///|
struct MdListItem {
  content : Array[Inline]
  children : Array[Block]
} derive(Eq, Debug)

///|
/// Inline parsers
pub let special_chars = "]*_`[!\\"

///|
pub let delim_char : (Char) -> String = c => "'\{c}'"

///|
pub type InlineParser = @talcparsec.StringParser[Inline]

///|
pub type BlockParser = @talcparsec.StringParser[Block]

///|
pub type SParser = @talcparsec.StringParser[String]

///|
let escaped : InlineParser = @talcparsec.char('\\')
  .then(@talcparsec.one_of(special_chars))
  .map(c => Plain(c.to_string()))

///|
let code_span : InlineParser = @talcparsec.char('`')
  .then(@talcparsec.many_chars(@talcparsec.none_of("`")))
  .skip(@talcparsec.char('`'))
  .map(c => Code(c))

///|
let link_url : SParser = @talcparsec.char('(')
  .then(@talcparsec.many_chars(@talcparsec.none_of(")")))
  .skip(@talcparsec.char(')'))

///|
fn link() -> InlineParser {
  let not_bracket = @talcparsec.char(']').not_followed_by(delim_char(']'))
  @talcparsec.char('[')
  .then(not_bracket.then(inline()).some())
  .skip(@talcparsec.char(']'))
  .bind(text => link_url.map(url => Link(text, url)))
}

///|
let image : InlineParser = @talcparsec.char('!')
  .then(@talcparsec.char('['))
  .then(@talcparsec.many_chars(@talcparsec.none_of("]")))
  .skip(@talcparsec.char(']'))
  .bind(alt => link_url.map(url => Image(alt, url)))

///|
fn strong() -> InlineParser {
  let not_star = @talcparsec.char('*').not_followed_by(delim_char('*'))
  @talcparsec.char('*')
  .then(not_star.then(inline()).some())
  .skip(@talcparsec.char('*'))
  .map(c => Strong(c))
}

///|
fn emph() -> InlineParser {
  let not_uscore = @talcparsec.char('_').not_followed_by(delim_char('_'))
  @talcparsec.char('_')
  .then(not_uscore.then(inline()).some())
  .skip(@talcparsec.char('_'))
  .map(c => Emph(c))
}

///|
let plain_char : InlineParser = {
  let non_special = @talcparsec.none_of(special_chars)
  non_special.bind(c => {
    @talcparsec.many_chars(non_special).map(rest => Plain(c.to_string() + rest))
  })
}

///|
fn inline() -> InlineParser {
  @talcparsec.delay(() => {
    @talcparsec.choice([
      escaped,
      image,
      link(),
      strong(),
      emph(),
      code_span,
      plain_char,
    ])
  })
}

///|
fn parse_inlines(
  text : String,
) -> Result[Array[Inline], @talcparsec.ParseError] {
  inline().some().parse(@talcparsec.Input::new(text))
}

///|
/// Block parsers
let blank_line : @talcparsec.StringParser[Unit] = {
  let ws_no_nl = @talcparsec.satisfy("non-nl whitespace", c => {
    Char::is_whitespace(c) && c != '\n'
  })
  @talcparsec.many_chars(ws_no_nl).skip(@talcparsec.char('\n')).map(_ => ())
}

///|
let thematic_break : BlockParser = @talcparsec.string("---")
  .then(@talcparsec.char('-').many())
  .skip(@talcparsec.char('\n'))
  .map(_ => ThematicBreak)

///|
let heading : BlockParser = @talcparsec.char('#')
  .some()
  .bind(hashes => {
    @talcparsec.char(' ').bind(_ => {
      @talcparsec.Parser::new(input => {
        @talcparsec.many_chars(@talcparsec.none_of("\n"))
        .run(input)
        .bind(pair => {
          let (text, rest) = pair
          parse_inlines(text).map(inlines => {
            (Heading(hashes.length(), inlines), rest)
          })
        })
      })
    })
  })

///|
let rest_of_line : SParser = @talcparsec.many_chars(@talcparsec.none_of("\n")).bind(content => {
    @talcparsec.char('\n').map(_ => content + "\n")
  },
)

///|
let fenced_code : BlockParser = {
  let not_nl = @talcparsec.satisfy("not newline", c => c != '\n')
  @talcparsec.string("```")
  .then(@talcparsec.many_chars1(not_nl).optional())
  .skip(@talcparsec.char('\n'))
  .bind(lang => {
    let terminator = @talcparsec.string("```").skip(@talcparsec.char('\n'))
    rest_of_line
    .many_until(terminator)
    .map(lines => FencedCode(lang, lines.join("")))
  })
}

///|
/// Quote
let quoted_line : SParser = @talcparsec.char('>')
  .then(@talcparsec.char(' ').optional())
  .then(rest_of_line)

///|
fn blockquote() -> BlockParser {
  quoted_line
  .some()
  .bind(lines => {
    @talcparsec.Parser::new(input => {
      block()
      .some()
      .parse(@talcparsec.Input::new(lines.join("")))
      .map(blocks => (Blockquote(blocks), input))
    })
  })
}

///|
/// Paragraph
let paragraph_line : SParser = blank_line
  .not_followed_by("blank line")
  .then(@talcparsec.char('#').not_followed_by("'#'"))
  .then(@talcparsec.string("---").not_followed_by("\"---\""))
  .then(@talcparsec.string("```").not_followed_by("\"```\""))
  .then(@talcparsec.char('>').not_followed_by("'>'"))
  .then(
    @talcparsec.char('-').then(@talcparsec.char(' ')).not_followed_by("'- '"),
  )
  .then(
    @talcparsec.char('+').then(@talcparsec.char(' ')).not_followed_by("'+ '"),
  )
  .then(rest_of_line)

///|
let paragraph : BlockParser = paragraph_line
  .some()
  .bind(lines => {
    let text = lines.join("").trim_end().to_owned()
    @talcparsec.Parser::new(input => {
      parse_inlines(text).map(inlines => (Paragraph(inlines), input))
    })
  })

///|
/// Lists
fn list_item(
  marker : Char,
  indent : Int,
) -> @talcparsec.StringParser[MdListItem] {
  let istr = String::repeat(" ", indent)
  @talcparsec.string(istr)
  .then(@talcparsec.char(marker))
  .skip(@talcparsec.char(' '))
  .bind(_ => {
    @talcparsec.Parser::new(input => {
      match @talcparsec.many_chars(@talcparsec.none_of("\n")).run(input) {
        Ok((text, rest)) =>
          match parse_inlines(text) {
            Ok(content) =>
              match @talcparsec.char('\n').run(rest) {
                Ok((_, after_nl)) =>
                  sub_list(indent + 2)
                  .many()
                  .run(after_nl)
                  .map(pair => {
                    let (children, rest2) = pair
                    ({ content, children }, rest2)
                  })
                Err(_) =>
                  sub_list(indent + 2)
                  .many()
                  .run(rest)
                  .map(pair => {
                    let (children, rest2) = pair
                    ({ content, children }, rest2)
                  })
              }
            Err(e) => Err(e)
          }
        Err(e) => Err(e)
      }
    })
  })
}

///|
fn unordered_list_at(indent : Int) -> BlockParser {
  list_item('-', indent).some().map(items => UnorderedList(items))
}

///|
fn ordered_list_at(indent : Int) -> BlockParser {
  list_item('+', indent).some().map(items => OrderedList(items))
}

///|
fn sub_list(indent : Int) -> BlockParser {
  @talcparsec.choice([unordered_list_at(indent), ordered_list_at(indent)])
}

///|
let unordered_list : BlockParser = unordered_list_at(0)

///|
let ordered_list : BlockParser = ordered_list_at(0)

///|
/// Document
fn block() -> BlockParser {
  @talcparsec.choice([
    thematic_break,
    heading,
    fenced_code,
    blockquote(),
    unordered_list,
    ordered_list,
    paragraph,
  ])
}

///|
let block_sep : @talcparsec.StringParser[Array[Unit]] = blank_line.some()

///|
let document : @talcparsec.StringParser[Array[Block]] = blank_line
  .many()
  .then(block().sep_by(block_sep))
  .skip(blank_line.many())
  .skip(@talcparsec.eof())

///|
test "full document" {
  let markdown =
    #|# Title
    #|
    #|A paragraph with *strong*, _emph_, `code`, a [link](u) and an ![img](i.png).
    #|
    #|---
    #|
    #|> A *quote* with `code`
    #|> in two lines
    #|
    #|```python
    #|print("hello")
    #|```
    #|
    #|- first item
    #|- second with *nested*
    #|  - sub-item
    #|  - another sub
    #|
  @test.assert_eq(
    document.parse(@talcparsec.Input::new(markdown)),
    Ok([
      Heading(1, [Plain("Title")]),
      Paragraph([
        Plain("A paragraph with "),
        Strong([Plain("strong")]),
        Plain(", "),
        Emph([Plain("emph")]),
        Plain(", "),
        Code("code"),
        Plain(", a "),
        Link([Plain("link")], "u"),
        Plain(" and an "),
        Image("img", "i.png"),
        Plain("."),
      ]),
      ThematicBreak,
      Blockquote([Paragraph([
        Plain("A "),
        Strong([Plain("quote")]),
        Plain(" with "),
        Code("code"),
        Plain("\nin two lines"),
      ])]),
      FencedCode(Some("python"), "print(\"hello\")\n"),
      UnorderedList([
        { content: [Plain("first item")], children: [] },
        {
          content: [Plain("second with "), Strong([Plain("nested")])],
          children: [
            UnorderedList([
              { content: [Plain("sub-item")], children: [] },
              { content: [Plain("another sub")], children: [] },
            ]),
          ],
        },
      ]),
    ]),
  )
}

///|
test "escaped character" {
  @test.assert_eq(escaped.parse(@talcparsec.Input::new("\\*")), Ok(Plain("*")))
  @test.assert_eq(
    escaped.parse(@talcparsec.Input::new("\\\\")),
    Ok(Plain("\\")),
  )
  match escaped.parse(@talcparsec.Input::new("\\a")) {
    Err(_) => ()
    Ok(_) => @test.fail("expected fail on non-special char")
  }
}

///|
test "code span" {
  @test.assert_eq(
    code_span.parse(@talcparsec.Input::new("`code`")),
    Ok(Code("code")),
  )
  @test.assert_eq(code_span.parse(@talcparsec.Input::new("``")), Ok(Code("")))
}

///|
test "strong and emph" {
  @test.assert_eq(
    strong().parse(@talcparsec.Input::new("*bold*")),
    Ok(Strong([Plain("bold")])),
  )
  @test.assert_eq(
    emph().parse(@talcparsec.Input::new("_italic_")),
    Ok(Emph([Plain("italic")])),
  )
  @test.assert_eq(
    strong().parse(@talcparsec.Input::new("*bold _and_ italic*")),
    Ok(Strong([Plain("bold "), Emph([Plain("and")]), Plain(" italic")])),
  )
}

///|
test "link and image" {
  @test.assert_eq(
    link().parse(@talcparsec.Input::new("[text](url)")),
    Ok(Link([Plain("text")], "url")),
  )
  @test.assert_eq(
    image.parse(@talcparsec.Input::new("![alt](img.png)")),
    Ok(Image("alt", "img.png")),
  )
}

///|
test "inline plain text and mixed" {
  @test.assert_eq(parse_inlines("hello"), Ok([Plain("hello")]))
  @test.assert_eq(
    parse_inlines("hello *world*"),
    Ok([Plain("hello "), Strong([Plain("world")])]),
  )
  @test.assert_eq(
    parse_inlines("a `b` c"),
    Ok([Plain("a "), Code("b"), Plain(" c")]),
  )
}

///|
test "thematic break" {
  @test.assert_eq(
    thematic_break.parse(@talcparsec.Input::new("---\n")),
    Ok(ThematicBreak),
  )
  @test.assert_eq(
    thematic_break.parse(@talcparsec.Input::new("--------\n")),
    Ok(ThematicBreak),
  )
}

///|
test "heading" {
  @test.assert_eq(
    heading
    .skip(@talcparsec.char('\n'))
    .parse(@talcparsec.Input::new("# Title\n")),
    Ok(Heading(1, [Plain("Title")])),
  )
  @test.assert_eq(
    heading
    .skip(@talcparsec.char('\n'))
    .parse(@talcparsec.Input::new("### Sub *bold*\n")),
    Ok(Heading(3, [Plain("Sub "), Strong([Plain("bold")])])),
  )
}

///|
test "fenced code" {
  @test.assert_eq(
    fenced_code.parse(@talcparsec.Input::new("```\ncode\n```\n")),
    Ok(FencedCode(None, "code\n")),
  )
  @test.assert_eq(
    fenced_code.parse(@talcparsec.Input::new("```\nline1\nline2\n```\n")),
    Ok(FencedCode(None, "line1\nline2\n")),
  )
  @test.assert_eq(
    fenced_code.parse(@talcparsec.Input::new("```rust\nfn main() {}\n```\n")),
    Ok(FencedCode(Some("rust"), "fn main() {}\n")),
  )
}

///|
test "paragraph" {
  @test.assert_eq(
    paragraph.parse(@talcparsec.Input::new("hello world\n")),
    Ok(Paragraph([Plain("hello world")])),
  )
  @test.assert_eq(
    paragraph.parse(@talcparsec.Input::new("hello *world* ok\n")),
    Ok(Paragraph([Plain("hello "), Strong([Plain("world")]), Plain(" ok")])),
  )
}

///|
test "blockquote" {
  @test.assert_eq(
    blockquote().parse(@talcparsec.Input::new("> hello\n> *world*\n")),
    Ok(Blockquote([Paragraph([Plain("hello\n"), Strong([Plain("world")])])])),
  )
}

///|
test "unordered list" {
  @test.assert_eq(
    unordered_list.parse(@talcparsec.Input::new("- one\n- two\n")),
    Ok(
      UnorderedList([
        { content: [Plain("one")], children: [] },
        { content: [Plain("two")], children: [] },
      ]),
    ),
  )
}

///|
test "ordered list" {
  @test.assert_eq(
    ordered_list.parse(@talcparsec.Input::new("+ first\n+ second\n")),
    Ok(
      OrderedList([
        { content: [Plain("first")], children: [] },
        { content: [Plain("second")], children: [] },
      ]),
    ),
  )
}

///|
test "nested list" {
  @test.assert_eq(
    unordered_list.parse(@talcparsec.Input::new("- a\n  - b\n  - c\n")),
    Ok(
      UnorderedList([
        {
          content: [Plain("a")],
          children: [
            UnorderedList([
              { content: [Plain("b")], children: [] },
              { content: [Plain("c")], children: [] },
            ]),
          ],
        },
      ]),
    ),
  )
}

///|
test "document with fenced code and blockquote" {
  let md = "> quote\n\n```\ncode\n```\n"
  @test.assert_eq(
    document.parse(@talcparsec.Input::new(md)),
    Ok([Blockquote([Paragraph([Plain("quote")])]), FencedCode(None, "code\n")]),
  )
}

///|
test "document with thematic break" {
  let md = "a\n\n---\n\nb\n"
  @test.assert_eq(
    document.parse(@talcparsec.Input::new(md)),
    Ok([Paragraph([Plain("a")]), ThematicBreak, Paragraph([Plain("b")])]),
  )
}

///|
test "strict mode: unmatched delimiter fails" {
  match parse_inlines("*unclosed") {
    Err(_) => ()
    Ok(_) => @test.fail("expected fail on unmatched '*'")
  }
}
