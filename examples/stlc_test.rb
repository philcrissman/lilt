require "minitest/autorun"
require_relative "stlc"

class STLCTest < Minitest::Test
  include STLC

  PROGRAM      = "(λf:Bool -> Bool. f true) \\x:Bool. if x then false else x"
  SEXP_PROGRAM = "((lambda (f (-> Bool Bool)) (f true)) (lambda (x Bool) (if x false x)))"

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
    assert_equal Lam.new(:x, TBool.new, Var.new(:x)), parse("λx:Bool. x")
  end

  def test_lambda_body_extends_as_far_right_as_possible
    f, x = Var.new(:f), Var.new(:x)

    assert_equal Lam.new(:x, TBool.new, App.new(f, x)), parse("λx:Bool. f x")
  end

  def test_arrow_types_are_right_associative
    b = TBool.new

    assert_equal Lam.new(:f, TArrow.new(b, TArrow.new(b, b)), Var.new(:f)),
                 parse("λf:Bool -> Bool -> Bool. f")
  end

  def test_parentheses_group_types
    b = TBool.new

    assert_equal Lam.new(:f, TArrow.new(TArrow.new(b, b), b), Var.new(:f)),
                 parse("λf:(Bool -> Bool) -> Bool. f")
  end

  def test_parses_a_whole_program
    b, f, x = TBool.new, Var.new(:f), Var.new(:x)

    assert_equal App.new(Lam.new(:f, TArrow.new(b, b), App.new(f, Bool.new(true))),
                         Lam.new(:x, b, If.new(x, Bool.new(false), x))),
                 parse(PROGRAM)
  end

  def test_from_sexp_reads_a_variable
    assert_equal Var.new(:x), from_sexp("x")
  end

  def test_from_sexp_reads_booleans
    assert_equal Bool.new(true), from_sexp("true")
    assert_equal Bool.new(false), from_sexp("false")
  end

  def test_from_sexp_reads_a_lambda
    assert_equal Lam.new(:x, TBool.new, Var.new(:x)), from_sexp("(lambda (x Bool) x)")
  end

  def test_from_sexp_reads_if
    assert_equal If.new(Var.new(:x), Bool.new(false), Bool.new(true)), from_sexp("(if x false true)")
  end

  def test_from_sexp_reads_application_curried
    f, x, y = Var.new(:f), Var.new(:x), Var.new(:y)

    assert_equal App.new(f, x), from_sexp("(f x)")
    assert_equal App.new(App.new(f, x), y), from_sexp("(f x y)")
  end

  def test_from_sexp_reads_arrow_types_curried
    b = TBool.new

    assert_equal Lam.new(:f, TArrow.new(b, b), Var.new(:f)), from_sexp("(lambda (f (-> Bool Bool)) f)")
    assert_equal Lam.new(:f, TArrow.new(b, TArrow.new(b, b)), Var.new(:f)),
                 from_sexp("(lambda (f (-> Bool Bool Bool)) f)")
  end

  def test_both_front_ends_produce_the_same_ast
    assert_equal parse(PROGRAM), from_sexp(SEXP_PROGRAM)
  end
end
