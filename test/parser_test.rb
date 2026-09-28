# frozen_string_literal: true

require "test_helper"

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
  def at(positions, node) = positions.fetch(node).then { [_1.line, _1.col] }

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

  def test_parse_located_records_where_each_node_starts
    ast, positions = Prattle.parse_located(ARITH, tokens("f x + y"))

    assert_equal Add.new(App.new(*vars("f", "x")), Var.new("y")), ast
    assert_equal [1, 1], at(positions, ast)
    assert_equal [1, 1], at(positions, ast.left)
    assert_equal [1, 3], at(positions, ast.left.arg)
    assert_equal [1, 7], at(positions, ast.right)
  end

  def test_parse_located_tells_equal_nodes_apart
    ast, positions = Prattle.parse_located(ARITH, tokens("x + x"))

    assert_equal ast.left, ast.right
    assert_equal [1, 1], at(positions, ast.left)
    assert_equal [1, 5], at(positions, ast.right)
  end

  def test_advance_never_moves_past_eof
    parser = Prattle::Parser.new(tokens("a"))
    parser.advance

    assert_equal :eof, parser.advance.type
    assert_equal :eof, parser.advance.type
  end
end
