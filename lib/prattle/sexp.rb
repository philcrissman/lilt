# frozen_string_literal: true

require_relative "lexer"
require_relative "parser"

module Prattle
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
