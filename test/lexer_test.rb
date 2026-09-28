# frozen_string_literal: true

require "test_helper"

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
