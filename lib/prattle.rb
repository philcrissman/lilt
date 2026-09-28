# frozen_string_literal: true

require "strscan"
require_relative "prattle/version"

module Prattle
  extend self

  Token = Data.define(:type, :value, :line, :col)

  class LexError < StandardError; end
  class ParseError < StandardError; end

  def parse(table, tokens) = parse_located(table, tokens).first

  # Like parse, but also returns a Hash (compared by identity) from each node
  # a handler built to the token where that node's expression starts.
  def parse_located(table, tokens)
    parser = Parser.new(tokens)
    ast = parser.parse(table).tap { parser.expect(:eof) }
    [ast, parser.positions]
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
    attr_reader :positions

    def initialize(tokens)
      @tokens = tokens
      @pos = 0
      @positions = {}.compare_by_identity
    end

    def parse(table, min_bp = 0)
      start = advance
      nud = table.fetch(:prefix)[start.type] or error!(start, "unexpected #{start.type}")
      left = locate(nud.call(start, self, table), start)

      loop do
        bp, led = led_for(table, peek)
        break if bp.nil? || bp <= min_bp
        left = locate(led.call(left), start)
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

    # Records where +node+ starts, unless an inner parse already did (as when
    # a group handler returns its inner expression). Returns +node+.
    def locate(node, tok)
      @positions[node] ||= tok
      node
    end

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

  module Sexp
    extend self

    RULES = [[/\s+/, nil], ["(", :lparen], [")", :rparen], [/[^\s()]+/, :atom]]

    def read(source)
      parser = Parser.new(Lexer.lex(source, RULES))
      datum(parser).tap { parser.expect(:eof) }
    end

    def print(node)
      case node
      in Data  then list([tag(node), *node.deconstruct])
      in Array then list(node)
      else node.to_s
      end
    end

    private

    def list(items) = "(#{items.map { print(_1) }.join(" ")})"

    def datum(parser)
      tok = parser.advance
      case tok.type
      when :lparen then items(parser)
      when :atom   then atom(tok.value)
      else parser.error!(tok, "unexpected #{tok.type}")
      end
    end

    def atom(text) = text.match?(/\A-?\d+\z/) ? text.to_i : text.to_sym

    def items(parser)
      list = []
      list << datum(parser) until parser.peek.type == :rparen
      parser.expect(:rparen)
      list
    end

    def tag(node)
      node.class.name.split("::").last
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
    end
  end
end
