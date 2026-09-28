# frozen_string_literal: true

require "test_helper"

class LiltTest < Minitest::Test
  def test_has_a_version_number
    refute_nil Lilt::VERSION
  end
end
