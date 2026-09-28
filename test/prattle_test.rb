# frozen_string_literal: true

require "test_helper"

class PrattleTest < Minitest::Test
  def test_has_a_version_number
    refute_nil Prattle::VERSION
  end
end
