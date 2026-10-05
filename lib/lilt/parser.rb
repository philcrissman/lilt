# frozen_string_literal: true

module Lilt
  extend self

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
    [bp, proc { |left, token, p, table| build.call(left, p.parse(table, right_bp), token) }]
  end

  # Builds a prefix handler for a prefix operator. The operand is parsed at
  # +bp+, so it takes in exactly the infix operators that bind tighter than
  # +bp+. The block receives the operand (and the operator token).
  def prefix(bp, &build)
    proc { |token, p, table| build.call(p.parse(table, bp), token) }
  end

  # Builds a prefix handler for a bracketing token: parses one expression in
  # the current table, then expects +close+. Returns the inner expression.
  def group(close)
    proc { |_token, p, table| p.parse(table).tap { p.expect(close) } }
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
      prefix = table.fetch(:prefix)[start.type] or error!(start, "unexpected #{start.type}")
      left = locate(prefix.call(start, self, table), start)

      loop do
        bp, infix = infix_for(table, peek)
        break if bp.nil? || bp <= min_bp
        left = locate(infix.call(left), start)
      end

      left
    end

    def peek = @tokens[@pos]

    def expect(type)
      token = peek
      error!(token, "expected #{type}, got #{token.type}") unless token.type == type
      advance
    end

    def advance
      token = @tokens[@pos]
      @pos += 1 unless token.type == :eof
      token
    end

    def error!(token, message) = raise(ParseError, "#{message} at #{token.line}:#{token.col}")

    private

    # Records where +node+ starts, unless an inner parse already did (as when
    # a group handler returns its inner expression). Returns +node+.
    def locate(node, token)
      @positions[node] ||= token
      node
    end

    # If +token+ can continue an expression, returns its binding power and a
    # callable that extends +left+. An infix entry consumes the operator
    # token; juxtaposition applies when +token+ can instead *start* an
    # expression, and consumes nothing before parsing the right side.
    def infix_for(table, token)
      if (infix = table.fetch(:infix, {})[token.type])
        bp, handler = infix
        return [bp, ->(left) { handler.call(left, advance, self, table) }]
      end

      bp, build = table[:juxtapose]
      return unless bp && table.fetch(:prefix).key?(token.type)

      [bp, ->(left) { build.call(left, parse(table, bp)) }]
    end
  end
end
