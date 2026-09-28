# frozen_string_literal: true

require "test_helper"

class SexpTest < Minitest::Test
  Var    = Data.define(:name)
  TBool  = Data.define
  TArrow = Data.define(:from, :to)

  def test_prints_a_data_node_as_a_tagged_list
    assert_equal "(var x)", Lilt::Sexp.print(Var.new("x"))
  end

  def test_prints_nested_nodes_with_snake_case_tags
    assert_equal "(t_arrow (t_bool) (t_bool))", Lilt::Sexp.print(TArrow.new(TBool.new, TBool.new))
  end

  def test_prints_arrays_as_untagged_lists
    assert_equal "(lambda (x Bool) x)", Lilt::Sexp.print([:lambda, [:x, :Bool], :x])
    assert_equal "()", Lilt::Sexp.print([])
  end

  def test_reads_a_symbol
    assert_equal :x, Lilt::Sexp.read("x")
  end

  def test_reads_nested_lists
    assert_equal [:lambda, [:x, :Bool], [:f, :x]], Lilt::Sexp.read("(lambda (x Bool) (f x))")
    assert_equal [], Lilt::Sexp.read("()")
  end

  def test_unbalanced_parens_raise_parse_errors
    error = assert_raises(Lilt::ParseError) { Lilt::Sexp.read("(a") }
    assert_equal "unexpected eof at 1:3", error.message

    error = assert_raises(Lilt::ParseError) { Lilt::Sexp.read(")") }
    assert_equal "unexpected rparen at 1:1", error.message
  end

  def test_reads_integers_as_integers
    assert_equal [:succ, 42, -7], Lilt::Sexp.read("(succ 42 -7)")
    assert_equal [:x1, :"1x", :-], Lilt::Sexp.read("(x1 1x -)")
  end

  def test_print_round_trips_what_read_reads
    source = "(lambda (x Bool) (f x 42))"

    assert_equal source, Lilt::Sexp.print(Lilt::Sexp.read(source))
  end
end
