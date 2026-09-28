require "rake/testtask"

Rake::TestTask.new do |t|
  t.test_files = FileList["prattle_test.rb", "examples/*_test.rb"]
  t.warning = true
end

task default: :test
