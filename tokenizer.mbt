///|
/// Character-level and token-level primitive parsers.
///
/// Defines the fundamental character parsers (`char`, `satisfy`, `string`,
/// `take_while`, etc.), generic token parser `satisfy_input`, whitespace
/// helpers, and pre-built convenience parsers for line-oriented input.

///|
pub fn[I : Cursor, E : ParseFailure] eof() -> ParserRaw[I, Unit, E] {
  ParserRaw::new(input => {
    guard input.is_at_eof() else {
      Err(ParseFailure::signal(input, "end of input"))
    }
    Ok(((), input))
  })
}

///|
pub fn[I : Cursor, T, E : ParseFailure] satisfy_input(
  next : (I) -> (T, I)?,
  name : String,
  predicate : (T) -> Bool,
) -> ParserRaw[I, T, E] {
  ParserRaw::new(input => {
    guard next(input) is Some((token, rest)) else {
      Err(ParseFailure::signal(input, name))
    }
    guard predicate(token) else { Err(ParseFailure::signal(input, name)) }
    Ok((token, rest))
  })
}

///|
pub fn[E : ParseFailure] char(expected : Char) -> ParserRaw[Input, Char, E] {
  satisfy("'\{expected}'", ch => ch == expected)
}

///|
#inline
pub fn[E : ParseFailure] satisfy(
  name : String,
  predicate : (Char) -> Bool,
) -> ParserRaw[Input, Char, E] {
  ParserRaw::new(input => {
    guard input.peek() is Some(ch) && predicate(ch) else {
      Err(ParseFailure::signal(input, name))
    }
    Ok((ch, input.advance(ch)))
  })
}

///|
/// Skip complete ASCII whitespace blocks; scalar decoding handles Unicode
/// whitespace, short tails and the first non-whitespace character.
#warnings("-alert_experimental")
fn skip_ws(input : Input) -> Input {
  let source = input.source
  let length = source.length()
  for offset = input.offset {
    guard source.get_char(offset) is Some(ch) && ch.is_whitespace() else {
      break { ..input, offset, }
    }
    let next = if UseSimd {
      let space = @v128.i16x8_splat(32)
      let tab = @v128.i16x8_splat(9)
      let carriage_return = @v128.i16x8_splat(13)
      for next = offset + ch.utf16_len(); next <= length - 8; {
        let block = @v128.v128_load_i16x8(source, next)
        let spaces = @v128.i16x8_eq(block, space)
        let controls = @v128.v128_and_(
          @v128.i16x8_ge_u(block, tab),
          @v128.i16x8_le_u(block, carriage_return),
        )
        let whitespace = @v128.v128_or_(spaces, controls)
        guard !@v128.v128_any_true(@v128.v128_not(whitespace)) else {
          break next
        }
        continue next + 8
      } nobreak {
        next
      }
    } else {
      offset + ch.utf16_len()
    }
    continue next
  }
}

///|
pub fn[E] skip_spaces() -> ParserRaw[Input, Unit, E] {
  ParserRaw::new(input => Ok(((), skip_ws(input))))
}

///|
#valtype
priv struct AsciiTable {
  bits_0_31 : UInt
  bits_32_63 : UInt
  bits_64_95 : UInt
  bits_96_127 : UInt
}

///|
fn ascii_table(chars : String) -> AsciiTable {
  let mut bits_0_31 = 0U
  let mut bits_32_63 = 0U
  let mut bits_64_95 = 0U
  let mut bits_96_127 = 0U
  for offset in 0..<chars.length() {
    let cp = chars[offset].to_int()
    let bit = 1U << (cp & 31)
    match cp >> 5 {
      0 => bits_0_31 = bits_0_31 | bit
      1 => bits_32_63 = bits_32_63 | bit
      2 => bits_64_95 = bits_64_95 | bit
      3 => bits_96_127 = bits_96_127 | bit
      _ => ()
    }
  }
  { bits_0_31, bits_32_63, bits_64_95, bits_96_127, }
}

///|
fn AsciiTable::contains(self : AsciiTable, cp : Int) -> Bool {
  let bits = match cp >> 5 {
    0 => self.bits_0_31
    1 => self.bits_32_63
    2 => self.bits_64_95
    _ => self.bits_96_127
  }
  (bits & (1U << (cp & 31))) != 0U
}

///|
pub fn[E : ParseFailure] one_of(chars : String) -> ParserRaw[Input, Char, E] {
  let table = ascii_table(chars)
  satisfy("one of \{chars}", ch => {
    let cp = ch.to_int()
    if cp < 128 {
      table.contains(cp)
    } else {
      chars.contains_char(ch)
    }
  })
}

///|
pub fn[E : ParseFailure] none_of(chars : String) -> ParserRaw[Input, Char, E] {
  let table = ascii_table(chars)
  satisfy("none of \{chars}", ch => {
    let cp = ch.to_int()
    if cp < 128 {
      !table.contains(cp)
    } else {
      !chars.contains_char(ch)
    }
  })
}

///|
pub fn[E : ParseFailure] string(
  expected : String,
) -> ParserRaw[Input, String, E] {
  ParserRaw::new(input => {
    guard input.remaining().has_prefix(expected.to_string_view()) else {
      Err(ParseFailure::signal(input, "\"\{expected}\""))
    }
    Ok((expected, input.advance_string(expected)))
  })
}

///|
pub fn[E : ParseFailure] take_while(
  name : String,
  predicate : (Char) -> Bool,
) -> ParserRaw[Input, String, E] {
  ParserRaw::new(input => {
    let end = for offset = input.offset {
      guard input.source.get_char(offset) is Some(ch) && predicate(ch) else {
        break offset
      }
      continue offset + ch.utf16_len()
    }
    guard end > input.offset else { Err(ParseFailure::signal(input, name)) }
    let text = input.source[input.offset:end].to_owned()
    Ok((text, { ..input, offset: end, }))
  })
}

///|
pub fn[E : ParseFailure] ascii_digit() -> ParserRaw[Input, Char, E] {
  satisfy("ASCII digit", Char::is_ascii_digit)
}

///|
pub fn[E : ParseFailure] ascii_letter() -> ParserRaw[Input, Char, E] {
  satisfy("ASCII letter", Char::is_ascii_alphabetic)
}

///|
pub fn[E : ParseFailure] whitespace() -> ParserRaw[Input, Char, E] {
  satisfy("whitespace", Char::is_whitespace)
}

///|
pub fn[E] spaces() -> ParserRaw[Input, Array[Char], E] {
  ParserRaw::new(input => {
    let chars = Array()
    let rest = for offset = input.offset {
      guard input.source.get_char(offset) is Some(ch) && ch.is_whitespace() else {
        break { ..input, offset, }
      }
      chars.push(ch)
      continue offset + ch.utf16_len()
    }
    Ok((chars, rest))
  })
}

/// --- Pre-built convenience parsers --------------------------------------

///|
pub let space : CParser = char(' ')

///|
pub let newline : CParser = char('\r')
  .then(char('\n'))
  .map(_ => '\n')
  .or(char('\n'))

///|
pub let not_newline : CParser = satisfy("not newline", c => {
  c != '\n' && c != '\r'
})

///|
pub let line_content : SParser = many_chars(not_newline)

///|
/// Maps content `c` to a parser that consumes a newline and returns `c` +
/// a newline character.
pub let with_line : (String) -> SParser = c => newline.map(_ => "\{c}\n")

///|
/// Consumes all non-newline characters, then consumes the trailing newline.
///
/// Returns the matched line content including the newline terminator.
pub let rest_of_line : SParser = line_content.bind(with_line)
