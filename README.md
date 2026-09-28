# Lilt

A **Li**ttle **L**anguage **T**oolkit.

I've been writing a lot of small languages, mostly lambda calculi and similar experiments, 
from [TAPL](https://www.cis.upenn.edu/~bcpierce/tapl/) or other sources. I started to notice that the lexer and parser were all generally
the same, and were not the most interesting part of the process, so I thought I would try 
to create a library to make it easier to get a lexer and parser going for small languages.

It has:

- **A table-driven lexer.** You write the rules for recognizing tokens, and get back the 
  list of tokens with line and column numbers.
- **A Pratt parser engine.** You write tables of handlers, and get back whatever AST
  your handlers build.
- **An s-expression reader and printer.** It gives you a second front end for free, and
  a readable way to print any AST.

Grammars are plain data (arrays and hashes of procs), and the AST is yours: Lilt
doesn't define node types. I've been using `Data.define` for nodes, which gives you
structural equality and pattern matching for free.

## Installation

Add it to your Gemfile:

```ruby
gem "lilt"
```

or install it directly:

```sh
gem install lilt
```

It requires Ruby 3.2 or newer (for `Data`).

## Lexing

A lexer is a list of rules, each a pattern and a token type. Rules are tried in order,
and the first match wins. A string matches literally; a regex matches a pattern; a
`nil` type means "skip this".

```ruby
require "lilt"

RULES = [
  [/\s+/,      nil],      # skip whitespace
  ["+",        :plus],
  ["*",        :star],
  ["(",        :lparen],
  [")",        :rparen],
  [/\d+/,      :int],
  [/[a-z]\w*/, :ident],
]

Lilt::Lexer.lex("let x", RULES, keywords: %w[let])
# => [#<data Lilt::Token type=:let, value="let", line=1, col=1>,
#     #<data Lilt::Token type=:ident, value="x", line=1, col=5>,
#     #<data Lilt::Token type=:eof, value=nil, line=1, col=6>]
```

`keywords:` promotes any token whose whole text is a keyword to its own type, so `let`
becomes `:let` while `letter` stays an `:ident`. Every token list ends with `:eof`.
Columns count characters, not bytes, so `λ` is fine. Input that no rule matches raises
`Lilt::LexError` with its position.

## Parsing

A grammar table has `prefix:` handlers (for tokens that start an expression) and
`infix:` entries (for tokens that continue one). An infix entry is a binding power and a
handler; `Lilt.binary` builds the common case for you.

```ruby
Num = Data.define(:value)
Add = Data.define(:left, :right)
Mul = Data.define(:left, :right)

ARITH = {
  prefix: {
    int:    proc { |tok| Num.new(tok.value.to_i) },
    lparen: Lilt.group(:rparen),
  },
  infix: {
    plus: Lilt.binary(10) { |l, r| Add.new(l, r) },
    star: Lilt.binary(20) { |l, r| Mul.new(l, r) },
  },
}

ast = Lilt.parse(ARITH, Lilt::Lexer.lex("1 + 2 * 3", RULES))
# => #<data Add left=#<data Num value=1>, right=#<data Mul left=#<data Num value=2>, right=#<data Num value=3>>>

Lilt::Sexp.print(ast)
# => "(add (num 1) (mul (num 2) (num 3)))"
```

A higher binding power binds more tightly. `Lilt.binary(bp)` is left-associative;
`Lilt.binary(bp, :right)` is right-associative. `Lilt.group(:rparen)` parses one
expression and then expects the closing token.

For prefix operators like unary minus, `Lilt.prefix(bp) { |operand| Neg.new(operand) }`
parses its operand at `bp`. With a high `bp` (say 70), `-a * b` means `(-a) * b`; with
one between `*` and `^`, `-a ^ b` means `-(a ^ b)`. A token can have both a prefix and
an infix handler, so `-` can mean negation and subtraction.

Since the AST is just data, doing something with it is a `case`/`in`:

```ruby
def calc(e)
  case e
  in Num[n]    then n
  in Add[l, r] then calc(l) + calc(r)
  in Mul[l, r] then calc(l) * calc(r)
  end
end

calc(ast) # => 7
```

### Writing handlers

When a helper doesn't fit, a handler is just a proc:

- A **prefix** handler gets `(token, parser, table)`.
- An **infix** handler gets `(left, token, parser, table)`.
- An infix entry is `[binding_power, handler]`.

Inside a handler, `parser.parse(table, min_bp)` parses a sub-expression,
`parser.expect(:type)` consumes a token or raises, and `parser.peek` and
`parser.advance` look at and consume tokens. `parser.error!(token, message)` raises a
`Lilt::ParseError` with the token's position.

Procs ignore arguments they don't ask for, so simple handlers stay short.

### Application by juxtaposition

For functional languages, `f x y` means `(f x) y`. Add a `juxtapose:` entry and any
token that can *start* an expression, appearing where an operator could go, is treated
as an invisible, left-associative application operator:

```ruby
Var = Data.define(:name)
App = Data.define(:fn, :arg)

LC = {
  prefix: {
    ident:  proc { |tok| Var.new(tok.value.to_sym) },
    lparen: Lilt.group(:rparen),
  },
  infix: {
    plus: Lilt.binary(10) { |l, r| Add.new(l, r) },
  },
  juxtapose: [100, proc { |fn, arg| App.new(fn, arg) }],
}

Lilt::Sexp.print(Lilt.parse(LC, Lilt::Lexer.lex("f x y + g y", RULES)))
# => "(add (app (app (var f) (var x)) (var y)) (app (var g) (var y)))"
```

A real infix operator always wins over juxtaposition, and tokens with no prefix handler
(like `)`) end an application.

### Several tables

A grammar can have more than one table (terms and types, say), and a handler switches
between them just by parsing with a different one. For example, a lambda handler that
parses `λx:T. body` does `parser.parse(TYPES)` for the annotation and
`parser.parse(TERMS)` for the body. See `examples/stlc.rb`.

You need a separate table for each syntactic category: a part of the grammar where the
same tokens mean different things, or different operators apply. Many small languages,
like the untyped lambda calculus, have just one category, so one table is all they need.

### Errors and positions

Parse errors say where they happened:

```ruby
Lilt.parse(ARITH, Lilt::Lexer.lex("1 +", RULES))
# raises Lilt::ParseError: unexpected eof at 1:4
```

For errors found *after* parsing (type errors, say), `Lilt.parse_located` also
returns a table from each node to the token where it starts. The table is compared by
identity, so two equal nodes at different places in the source are told apart:

```ruby
ast, positions = Lilt.parse_located(ARITH, Lilt::Lexer.lex("1 + 2", RULES))
positions[ast.right] # => #<data Lilt::Token type=:int, value="2", line=1, col=5>
```

This keeps positions out of the AST, so structural equality still works. The STLC
example uses this to report type errors with a line and column, without its type checker
knowing anything about positions.

## S-expressions

`Lilt::Sexp.read` turns s-expression text into nested arrays of symbols and integers,
and `Lilt::Sexp.print` goes the other way. It also prints any `Data` node, using the
snake-cased class name as the tag:

```ruby
Lilt::Sexp.read("(lambda (x Bool) (f x 42))")
# => [:lambda, [:x, :Bool], [:f, :x, 42]]
```

This is handy for prototyping a language before its syntax has settled: write a small
function that turns the arrays into your AST, and get to the semantics without writing
a grammar at all. Later, the Pratt front end can produce the same AST.

## Is this really Pratt parsing?

Yes. The core loop is the one from Vaughan Pratt's 1973 paper *Top Down Operator
Precedence*, as popularized by Douglas Crockford. Prefix handlers are Pratt's *nud*s,
infix handlers are his *led*s, and parsing continues while the next token's binding power
is greater than the current minimum.

Lilt adds two things that aren't in the original:

- **Juxtaposition**, for function application.
- **Multiple tables** per grammar.

Within any one table, it's the standard algorithm. The lexer and the s-expression reader
aren't Pratt parsing; the reader is ordinary recursive descent.

## The STLC example

[`examples/stlc.rb`](examples/stlc.rb) is a complete simply typed lambda calculus with
booleans, built on Lilt in about 200 lines. It has:

- a Pratt grammar with two tables, terms and types
- an s-expression front end that produces the same AST, and a test checking that the two agree
- a type checker whose errors report line and column
- an environment-based evaluator with closures
- a De Bruijn index pass, with an evaluator for nameless terms

```ruby
STLC.interpret("(λx:Bool. if x then false else true) true")
# => #<data STLC::Bool value=false>

STLC.interpret("true false")
# raises STLC::TypeError: expected a function, got (t_bool) at 1:1
```

From a clone, try it with:

```sh
ruby -Ilib -r./examples/stlc -e 'p STLC.interpret("(λx:Bool. x) true")'
```

Its tests are in [`examples/stlc_test.rb`](examples/stlc_test.rb).

## Development

```sh
bundle install
bundle exec rake
```

`rake` runs the tests for the gem and the examples.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
