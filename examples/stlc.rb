require_relative "../prattle"

# The simply typed lambda calculus, with booleans.
#
#   λf:Bool -> Bool. f true                  (Pratt front end: STLC.parse)
#   (lambda (f (-> Bool Bool)) (f true))     (s-expression front end: STLC.from_sexp)
#
# Both front ends produce the same AST.
module STLC
  extend self

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

  # A runtime value: a function together with the scope it was created in.
  Closure = Data.define(:param, :body, :env)

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
      ident:  proc { |tok| Var.new(tok.value.to_sym) },
      true:   proc { Bool.new(true) },
      false:  proc { Bool.new(false) },
      lparen: Prattle.group(:rparen),
      lambda: proc { |_tok, p|
        param = p.expect(:ident).value.to_sym
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

  # The s-expression front end: turns Sexp.read output into the same AST.
  module FromSexp
    extend self

    def term(s)
      case s
      in :true | :false then Bool.new(s == :true)
      in Symbol         then Var.new(s)
      in [:lambda, [Symbol => x, t], body] then Lam.new(x, type(t), term(body))
      in [:if, c, t, e]                    then If.new(term(c), term(t), term(e))
      in [fn, *args] if args.any?          then args.reduce(term(fn)) { |f, a| App.new(f, term(a)) }
      end
    end

    def type(s)
      case s
      in :Bool                             then TBool.new
      in [:"->", *ts] if ts.size >= 2      then ts.map { type(_1) }.reverse.reduce { |to, from| TArrow.new(from, to) }
      end
    end
  end

  class TypeError < StandardError; end

  # The type checker: typeof(term, env) returns the term's type. +env+ maps
  # variable names to types.
  module Typing
    extend self

    def typeof(term, env = {})
      case term
      in Bool            then TBool.new
      in Var[x]          then env.fetch(x) { raise TypeError, "unbound variable #{x}" }
      in Lam[x, t, body] then TArrow.new(t, typeof(body, env.merge(x => t)))
      in App[fn, arg]
        case typeof(fn, env)
        in TArrow[from, to]
          actual = typeof(arg, env)
          raise TypeError, "expected argument of type #{show(from)}, got #{show(actual)}" unless actual == from
          to
        in other
          raise TypeError, "expected a function, got #{show(other)}"
        end
      in If[c, t, e]
        cond = typeof(c, env)
        raise TypeError, "condition must be #{show(TBool.new)}, got #{show(cond)}" unless cond == TBool.new
        then_, else_ = typeof(t, env), typeof(e, env)
        raise TypeError, "branches differ: #{show(then_)} vs #{show(else_)}" unless then_ == else_
        then_
      end
    end

    private

    def show(type) = Prattle::Sexp.print(type)
  end

  # The evaluator: evaluate(term, env) returns the term's value. +env+ maps
  # variable names to values. Assumes the term has already type-checked.
  module Eval
    extend self

    def evaluate(term, env = {})
      case term
      in Bool            then term
      in Var[x]          then env.fetch(x)
      in Lam[x, _, body] then Closure.new(x, body, env)
      in App[fn, arg]
        evaluate(fn, env) => Closure[x, body, captured]
        evaluate(body, captured.merge(x => evaluate(arg, env)))
      in If[c, t, e] then evaluate(evaluate(c, env).value ? t : e, env)
      end
    end
  end

  def lex(source)       = Prattle::Lexer.lex(source, RULES, keywords: KEYWORDS)
  def parse(source)     = Prattle.parse(TERMS, lex(source))
  def from_sexp(source) = FromSexp.term(Prattle::Sexp.read(source))

  # Parses, type-checks and evaluates +source+, returning its value.
  def interpret(source)
    term = parse(source)
    Typing.typeof(term)
    Eval.evaluate(term)
  end
end
