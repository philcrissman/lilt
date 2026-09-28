require "minitest/autorun"
require_relative "stlc"

class STLCTest < Minitest::Test
  include STLC

  PROGRAM      = "(λf:Bool -> Bool. f true) \\x:Bool. if x then false else x"
  SEXP_PROGRAM = "((lambda (f (-> Bool Bool)) (f true)) (lambda (x Bool) (if x false x)))"

  def ty(source)                = Prattle.parse(TYPES, lex(source))
  def type_of(source, env = {}) = Typing.typeof(parse(source), env)
  def value_of(source)          = Eval.evaluate(parse(source))
  def nameless(source)          = Nameless.remove_names(parse(source))

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

  def test_booleans_have_type_bool
    assert_equal TBool.new, Typing.typeof(parse("true"))
  end

  def test_variables_have_the_type_the_environment_gives_them
    assert_equal TBool.new, Typing.typeof(parse("x"), { x: TBool.new })
  end

  def test_unbound_variables_are_type_errors
    error = assert_raises(STLC::TypeError) { Typing.typeof(parse("x")) }
    assert_equal "unbound variable x", error.message
    assert_equal Var.new(:x), error.node
  end

  def test_a_lambda_has_an_arrow_type
    assert_equal ty("Bool -> Bool"), type_of("λx:Bool. x")
  end

  def test_an_inner_binder_shadows_an_outer_one
    assert_equal ty("Bool -> (Bool -> Bool) -> Bool -> Bool"), type_of("λx:Bool. λx:Bool -> Bool. x")
  end

  def test_applying_a_function_gives_its_result_type
    assert_equal ty("Bool"), type_of("f true", { f: ty("Bool -> Bool") })
  end

  def test_applying_a_non_function_is_a_type_error
    error = assert_raises(STLC::TypeError) { type_of("f true", { f: ty("Bool") }) }
    assert_equal "expected a function, got (t_bool)", error.message
    assert_equal Var.new(:f), error.node
  end

  def test_an_argument_of_the_wrong_type_is_a_type_error
    error = assert_raises(STLC::TypeError) { type_of("f true", { f: ty("(Bool -> Bool) -> Bool") }) }
    assert_equal "expected argument of type (t_arrow (t_bool) (t_bool)), got (t_bool)", error.message
    assert_equal Bool.new(true), error.node
  end

  def test_if_has_the_type_of_its_branches
    assert_equal ty("Bool -> Bool"), type_of("if c then f else λx:Bool. x", { c: ty("Bool"), f: ty("Bool -> Bool") })
  end

  def test_if_condition_must_be_bool
    error = assert_raises(STLC::TypeError) { type_of("if f then true else false", { f: ty("Bool -> Bool") }) }
    assert_equal "condition must be (t_bool), got (t_arrow (t_bool) (t_bool))", error.message
    assert_equal Var.new(:f), error.node
  end

  def test_if_branches_must_have_the_same_type
    error = assert_raises(STLC::TypeError) { type_of("if true then true else f", { f: ty("Bool -> Bool") }) }
    assert_equal "branches differ: (t_bool) vs (t_arrow (t_bool) (t_bool))", error.message
    assert_equal Var.new(:f), error.node
  end

  def test_type_checks_a_whole_program
    assert_equal ty("Bool"), Typing.typeof(parse(PROGRAM))
  end

  def test_booleans_evaluate_to_themselves
    assert_equal Bool.new(true), Eval.evaluate(parse("true"))
  end

  def test_a_lambda_evaluates_to_a_closure
    assert_equal Closure.new(:x, Var.new(:x), {}), value_of("λx:Bool. x")
  end

  def test_applying_a_closure_binds_its_parameter
    assert_equal Bool.new(false), value_of("(λx:Bool. x) false")
  end

  def test_closures_capture_their_defining_scope
    assert_equal Bool.new(true), value_of("(λx:Bool. λy:Bool. x) true false")
  end

  def test_if_evaluates_the_chosen_branch
    assert_equal Bool.new(false), value_of("if true then false else true")
    assert_equal Bool.new(true), value_of("if false then false else true")
  end

  def test_evaluates_a_whole_program
    assert_equal Bool.new(false), value_of(PROGRAM)
  end

  def test_interpret_type_checks_before_evaluating
    assert_equal Bool.new(false), interpret(PROGRAM)

    error = assert_raises(STLC::TypeError) { interpret("true false") }
    assert_equal "expected a function, got (t_bool) at 1:1", error.message
  end

  def test_interpret_points_type_errors_at_the_offending_subterm
    error = assert_raises(STLC::TypeError) { interpret("λf:Bool -> Bool.\n  f f") }
    assert_equal "expected argument of type (t_bool), got (t_arrow (t_bool) (t_bool)) at 2:5", error.message
  end

  def test_remove_names_turns_a_bound_variable_into_index_zero
    assert_equal ILam.new(TBool.new, Idx.new(0)), nameless("λx:Bool. x")
  end

  def test_an_index_counts_the_lambdas_between_use_and_binder
    b = TBool.new

    assert_equal ILam.new(b, ILam.new(b, Idx.new(1))), nameless("λx:Bool. λy:Bool. x")
    assert_equal ILam.new(b, ILam.new(b, Idx.new(0))), nameless("λx:Bool. λy:Bool. y")
  end

  def test_shadowed_names_refer_to_the_innermost_binder
    b = TBool.new

    assert_equal ILam.new(b, ILam.new(b, Idx.new(0))), nameless("λx:Bool. λx:Bool. x")
  end

  def test_alpha_equivalent_terms_become_equal
    refute_equal parse("λx:Bool. x"), parse("λy:Bool. y")
    assert_equal nameless("λx:Bool. x"), nameless("λy:Bool. y")
  end

  def test_remove_names_recurses_through_non_binding_forms
    b = TBool.new

    assert_equal App.new(ILam.new(TArrow.new(b, b), App.new(Idx.new(0), Bool.new(true))),
                         ILam.new(b, If.new(Idx.new(0), Bool.new(false), Idx.new(0)))),
                 nameless(PROGRAM)
  end

  def test_remove_names_rejects_unbound_variables
    error = assert_raises(STLC::TypeError) { nameless("λx:Bool. y") }
    assert_equal "unbound variable y", error.message
  end

  def test_a_nameless_lambda_evaluates_to_a_closure_over_an_array
    assert_equal IClosure.new(Idx.new(0), []), Nameless.evaluate(nameless("λx:Bool. x"))
  end

  def test_nameless_closures_capture_their_defining_scope
    assert_equal Bool.new(true), Nameless.evaluate(nameless("(λx:Bool. λy:Bool. x) true false"))
  end

  def test_named_and_nameless_evaluation_agree
    assert_equal value_of(PROGRAM), Nameless.evaluate(nameless(PROGRAM))
  end
end
