require "strscan"

module Prattle
  extend self

  Token = Data.define(:type, :value, :line, :col)

  class LexError < StandardError; end
  class ParseError < StandardError; end

  def parse(table, tokens)
    parser = Parser.new(tokens)
    parser.parse(table).tap { parser.expect(:eof) }
  end

  # Builds an infix entry for a binary operator. The block receives the
  # left and right operands (and the operator token) and returns the node.
  def binary(bp, assoc = :left, &build)
    right_bp = assoc == :right ? bp - 1 : bp
    [bp, proc { |left, tok, p, table| build.call(left, p.parse(table, right_bp), tok) }]
  end

  # Builds a prefix handler for a bracketing token: parses one expression in
  # the current table, then expects +close+. Returns the inner expression.
  def group(close)
    proc { |_tok, p, table| p.parse(table).tap { p.expect(close) } }
  end

  # A cursor over a token stream, which always ends with an :eof token.
  # Invariant: @pos always indexes a token; advance stops at :eof.
  class Parser
    def initialize(tokens)
      @tokens = tokens
      @pos = 0
    end

    def parse(table, min_bp = 0)
      tok = advance
      nud = table.fetch(:prefix)[tok.type] or error!(tok, "unexpected #{tok.type}")
      left = nud.call(tok, self, table)

      loop do
        bp, led = led_for(table, peek)
        break if bp.nil? || bp <= min_bp
        left = led.call(left)
      end

      left
    end

    def peek = @tokens[@pos]

    def expect(type)
      tok = peek
      error!(tok, "expected #{type}, got #{tok.type}") unless tok.type == type
      advance
    end

    def advance
      tok = @tokens[@pos]
      @pos += 1 unless tok.type == :eof
      tok
    end

    def error!(tok, message) = raise(ParseError, "#{message} at #{tok.line}:#{tok.col}")

    private

    # If +tok+ can continue an expression, returns its binding power and a
    # callable that extends +left+. An infix entry consumes the operator
    # token; juxtaposition applies when +tok+ can instead *start* an
    # expression, and consumes nothing before parsing the right side.
    def led_for(table, tok)
      if (infix = table.fetch(:infix, {})[tok.type])
        bp, handler = infix
        return [bp, ->(left) { handler.call(left, advance, self, table) }]
      end

      bp, build = table[:juxtapose]
      return unless bp && table.fetch(:prefix).key?(tok.type)

      [bp, ->(left) { build.call(left, parse(table, bp)) }]
    end
  end

  module Lexer
    extend self

    def lex(source, rules, keywords: [])
      scanner = StringScanner.new(source)
      tokens = []
      line, line_start = 1, 0

      until scanner.eos?
        start = scanner.charpos
        col = start - line_start + 1
        rule = rules.find { |pattern, _| scanner.scan(pattern) }
        raise LexError, "unexpected '#{source[start]}' at #{line}:#{col}" unless rule

        text = scanner.matched
        tokens << Token.new(token_type(rule.last, text, keywords), text, line, col) if rule.last
        line, line_start = advance(line, line_start, start, text)
      end

      tokens << Token.new(:eof, nil, line, scanner.charpos - line_start + 1)
    end

    private

    def token_type(type, text, keywords) = keywords.include?(text) ? text.to_sym : type

    # Returns the [line, line_start] in effect after consuming +text+ from +start+.
    def advance(line, line_start, start, text)
      nl = text.rindex("\n") or return [line, line_start]
      [line + text.count("\n"), start + nl + 1]
    end
  end
end
