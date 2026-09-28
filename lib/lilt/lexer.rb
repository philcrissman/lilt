# frozen_string_literal: true

require "strscan"

module Lilt
  Token = Data.define(:type, :value, :line, :col)

  class LexError < StandardError; end

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
