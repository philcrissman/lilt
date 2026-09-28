require "test_helper"

class PrattleTest < Minitest::Test
  def test_has_a_version_number
    refute_nil Prattle::VERSION
  end
end

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

class SexpTest < Minitest::Test
  Var    = Data.define(:name)
  TBool  = Data.define
  TArrow = Data.define(:from, :to)

  def test_prints_a_data_node_as_a_tagged_list
    assert_equal "(var x)", Prattle::Sexp.print(Var.new("x"))
  end

  def test_prints_nested_nodes_with_snake_case_tags
    assert_equal "(t_arrow (t_bool) (t_bool))", Prattle::Sexp.print(TArrow.new(TBool.new, TBool.new))
  end

  def test_prints_arrays_as_untagged_lists
    assert_equal "(lambda (x Bool) x)", Prattle::Sexp.print([:lambda, [:x, :Bool], :x])
    assert_equal "()", Prattle::Sexp.print([])
  end

  def test_reads_a_symbol
    assert_equal :x, Prattle::Sexp.read("x")
  end

  def test_reads_nested_lists
    assert_equal [:lambda, [:x, :Bool], [:f, :x]], Prattle::Sexp.read("(lambda (x Bool) (f x))")
    assert_equal [], Prattle::Sexp.read("()")
  end

  def test_unbalanced_parens_raise_parse_errors
    error = assert_raises(Prattle::ParseError) { Prattle::Sexp.read("(a") }
    assert_equal "unexpected eof at 1:3", error.message

    error = assert_raises(Prattle::ParseError) { Prattle::Sexp.read(")") }
    assert_equal "unexpected rparen at 1:1", error.message
  end

  def test_reads_integers_as_integers
    assert_equal [:succ, 42, -7], Prattle::Sexp.read("(succ 42 -7)")
    assert_equal [:x1, :"1x", :-], Prattle::Sexp.read("(x1 1x -)")
  end

  def test_print_round_trips_what_read_reads
    source = "(lambda (x Bool) (f x 42))"

    assert_equal source, Prattle::Sexp.print(Prattle::Sexp.read(source))
  end
end
