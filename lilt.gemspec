# frozen_string_literal: true

require_relative "lib/lilt/version"

Gem::Specification.new do |spec|
  spec.name = "lilt"
  spec.version = Lilt::VERSION
  spec.authors = ["Phil Crissman"]
  spec.email = ["phil.crissman@gmail.com"]

  spec.summary = "A small toolkit for building lexers and Pratt parsers for little languages."
  spec.description = <<~DESC.tr("\n", " ").strip
    Lilt provides a table-driven lexer, a Pratt (top-down operator precedence)
    parser engine extended with juxtaposition and multiple expression tables, position
    tracking, and an s-expression reader and printer. Grammars are plain data; ASTs are
    whatever your handlers build.
  DESC
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  # Once the repository is public, set spec.homepage and
  # spec.metadata["source_code_uri"] to its URL.

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile Rakefile .gitignore test/ examples/])
    end
  end
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
