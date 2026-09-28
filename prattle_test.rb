require "minitest/autorun"
require_relative "prattle"

class LexerTest < Minitest::Test
  Token = Prattle::Token
  INTS  = [[/\s+/, nil], [/\d+/, :int]]

  def test_lexes_a_single_token
    rules = [[/\d+/, :int]]

    assert_equal [Token.new(:int, "42", 1, 1), Token.new(:eof, nil, 1, 3)],
                 Prattle::Lexer.lex("42", rules)
  end

  def test_rules_with_nil_type_are_skipped
    assert_equal [Token.new(:int, "1", 1, 1), Token.new(:int, "23", 1, 4), Token.new(:eof, nil, 1, 6)],
                 Prattle::Lexer.lex("1  23", INTS)
  end

  def test_tracks_lines_and_columns_across_newlines
    assert_equal [Token.new(:int, "1", 1, 1), Token.new(:int, "23", 2, 3), Token.new(:eof, nil, 2, 5)],
                 Prattle::Lexer.lex("1\n  23", INTS)
  end

  def test_unmatched_input_raises_lex_error_with_position
    error = assert_raises(Prattle::LexError) { Prattle::Lexer.lex("1\n 2 $3", INTS) }
    assert_equal "unexpected '$' at 2:4", error.message
  end

  def test_columns_count_characters_not_bytes
    rules = [[/\s+/, nil], [/λ/, :lambda], [/[a-z]+/, :ident]]

    assert_equal [Token.new(:lambda, "λ", 1, 1), Token.new(:ident, "x", 1, 2),
                  Token.new(:lambda, "λ", 2, 1), Token.new(:ident, "y", 2, 3),
                  Token.new(:eof, nil, 2, 4)],
                 Prattle::Lexer.lex("λx\nλ y", rules)
  end

  def test_keywords_promote_exact_matches_to_their_own_type
    rules = [[/\s+/, nil], [/[a-z]+/, :ident]]

    assert_equal [Token.new(:if, "if", 1, 1), Token.new(:ident, "iffy", 1, 4),
                  Token.new(:then, "then", 1, 9), Token.new(:eof, nil, 1, 13)],
                 Prattle::Lexer.lex("if iffy then", rules, keywords: %w[if then])
  end

  def test_string_rules_match_literally
    # "." comes before the ident rule, so a regex-style "." would swallow "a".
    rules = [["->", :arrow], [".", :dot], [/[a-z]+/, :ident]]

    assert_equal [[:ident, "a"], [:arrow, "->"], [:ident, "b"], [:dot, "."], [:ident, "c"], [:eof, nil]],
                 Prattle::Lexer.lex("a->b.c", rules).map { [_1.type, _1.value] }
  end
end

class ParserTest < Minitest::Test
  Var = Data.define(:name)
  Add = Data.define(:left, :right)
  Mul = Data.define(:left, :right)
  Pow = Data.define(:left, :right)
  App = Data.define(:fn, :arg)

  ARITH = {
    prefix: {
      ident:  proc { |tok| Var.new(tok.value) },
      lparen: Prattle.group(:rparen),
    },
    infix:  {
      plus:  Prattle.binary(10) { |l, r| Add.new(l, r) },
      star:  Prattle.binary(20) { |l, r| Mul.new(l, r) },
      caret: Prattle.binary(30, :right) { |l, r| Pow.new(l, r) },
    },
    juxtapose: [100, proc { |fn, arg| App.new(fn, arg) }],
  }

  def tokens(source)
    Prattle::Lexer.lex(source, [[/\s+/, nil], ["+", :plus], ["*", :star], ["^", :caret],
                                ["(", :lparen], [")", :rparen], [/[a-z]+/, :ident]])
  end

  def parse(source) = Prattle.parse(ARITH, tokens(source))
  def vars(*names)  = names.map { Var.new(_1) }

  def test_parses_a_single_prefix_token
    table = { prefix: { ident: proc { |tok| Var.new(tok.value) } } }

    assert_equal Var.new("x"), Prattle.parse(table, tokens("x"))
  end

  def test_parses_an_infix_operator
    assert_equal Add.new(*vars("a", "b")), parse("a + b")
  end

  def test_same_power_is_left_associative
    a, b, c = vars("a", "b", "c")

    assert_equal Add.new(Add.new(a, b), c), parse("a + b + c")
  end

  def test_higher_power_binds_tighter
    a, b, c = vars("a", "b", "c")

    assert_equal Add.new(a, Mul.new(b, c)), parse("a + b * c")
    assert_equal Add.new(Mul.new(a, b), c), parse("a * b + c")
  end

  def test_parsing_right_side_one_below_own_power_is_right_associative
    a, b, c = vars("a", "b", "c")

    assert_equal Pow.new(a, Pow.new(b, c)), parse("a ^ b ^ c")
  end

  def test_parentheses_override_precedence
    a, b, c = vars("a", "b", "c")

    assert_equal Mul.new(Add.new(a, b), c), parse("(a + b) * c")
  end

  def test_juxtaposition_is_left_associative_application
    f, x, y = vars("f", "x", "y")

    assert_equal App.new(App.new(f, x), y), parse("f x y")
  end

  def test_juxtaposition_binds_tighter_than_infix_operators
    f, x, g, y = vars("f", "x", "g", "y")

    assert_equal Add.new(App.new(f, x), App.new(g, y)), parse("f x + g y")
  end

  def test_tokens_without_prefix_handlers_end_an_application
    f, x, y = vars("f", "x", "y")

    assert_equal App.new(App.new(f, x), y), parse("(f x) y")
    assert_equal App.new(f, App.new(x, y)), parse("f (x y)")
  end

  def test_expect_raises_parse_error_naming_what_it_wanted
    error = assert_raises(Prattle::ParseError) { parse("(a + b") }
    assert_equal "expected rparen, got eof at 1:7", error.message
  end

  def test_token_with_no_prefix_handler_raises_parse_error
    error = assert_raises(Prattle::ParseError) { parse("+ a") }
    assert_equal "unexpected plus at 1:1", error.message
  end

  def test_empty_input_raises_parse_error
    error = assert_raises(Prattle::ParseError) { parse("") }
    assert_equal "unexpected eof at 1:1", error.message
  end

  def test_leftover_tokens_raise_parse_error
    error = assert_raises(Prattle::ParseError) { parse("a )") }
    assert_equal "expected eof, got rparen at 1:3", error.message
  end

  def test_advance_never_moves_past_eof
    parser = Prattle::Parser.new(tokens("a"))
    parser.advance

    assert_equal :eof, parser.advance.type
    assert_equal :eof, parser.advance.type
  end
end

class STLCTest < Minitest::Test
  RULES = [
    [/\s+/,           nil],
    [/\\|λ/,          :lambda],
    ["->",            :arrow],
    [":",             :colon],
    [".",             :dot],
    ["(",             :lparen],
    [")",             :rparen],
    [/[A-Za-z_]\w*/,  :ident],
  ]
  KEYWORDS = %w[if then else true false Bool]

  Var    = Data.define(:name)
  Lam    = Data.define(:param, :type, :body)
  App    = Data.define(:fn, :arg)
  If     = Data.define(:cond, :then_, :else_)
  Bool   = Data.define(:value)
  TBool  = Data.define
  TArrow = Data.define(:from, :to)

  TYPES = {
    prefix: {
      Bool:   proc { TBool.new },
      lparen: Prattle.group(:rparen),
    },
    infix: {
      arrow: Prattle.binary(10, :right) { |from, to| TArrow.new(from, to) },
    },
  }

  TERMS = {
    prefix: {
      ident:  proc { |tok| Var.new(tok.value) },
      true:   proc { Bool.new(true) },
      false:  proc { Bool.new(false) },
      lparen: Prattle.group(:rparen),
      lambda: proc { |_tok, p|
        param = p.expect(:ident).value
        p.expect(:colon)
        type = p.parse(TYPES)
        p.expect(:dot)
        Lam.new(param, type, p.parse(TERMS))
      },
      if: proc { |_tok, p|
        cond = p.parse(TERMS)
        p.expect(:then)
        then_ = p.parse(TERMS)
        p.expect(:else)
        If.new(cond, then_, p.parse(TERMS))
      },
    },
    juxtapose: [100, proc { |fn, arg| App.new(fn, arg) }],
  }

  PROGRAM = "(λf:Bool -> Bool. f true) \\x:Bool. if x then false else x"

  def lex(source)   = Prattle::Lexer.lex(source, RULES, keywords: KEYWORDS)
  def parse(source) = Prattle.parse(TERMS, lex(source))

  def test_lexes_a_program
    assert_equal [[:lparen, "("], [:lambda, "λ"], [:ident, "f"], [:colon, ":"],
                  [:Bool, "Bool"], [:arrow, "->"], [:Bool, "Bool"], [:dot, "."],
                  [:ident, "f"], [:true, "true"], [:rparen, ")"],
                  [:lambda, "\\"], [:ident, "x"], [:colon, ":"], [:Bool, "Bool"], [:dot, "."],
                  [:if, "if"], [:ident, "x"], [:then, "then"], [:false, "false"],
                  [:else, "else"], [:ident, "x"], [:eof, nil]],
                 lex(PROGRAM).map { [_1.type, _1.value] }
  end

  def test_parses_a_lambda
    assert_equal Lam.new("x", TBool.new, Var.new("x")), parse("λx:Bool. x")
  end

  def test_lambda_body_extends_as_far_right_as_possible
    f, x = Var.new("f"), Var.new("x")

    assert_equal Lam.new("x", TBool.new, App.new(f, x)), parse("λx:Bool. f x")
  end

  def test_arrow_types_are_right_associative
    b = TBool.new

    assert_equal Lam.new("f", TArrow.new(b, TArrow.new(b, b)), Var.new("f")),
                 parse("λf:Bool -> Bool -> Bool. f")
  end

  def test_parentheses_group_types
    b = TBool.new

    assert_equal Lam.new("f", TArrow.new(TArrow.new(b, b), b), Var.new("f")),
                 parse("λf:(Bool -> Bool) -> Bool. f")
  end

  def test_parses_a_whole_program
    b, f, x = TBool.new, Var.new("f"), Var.new("x")

    assert_equal App.new(Lam.new("f", TArrow.new(b, b), App.new(f, Bool.new(true))),
                         Lam.new("x", b, If.new(x, Bool.new(false), x))),
                 parse(PROGRAM)
  end
end
