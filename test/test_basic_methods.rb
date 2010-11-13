require 'helper'

class TestBasicMethods < Test::Unit::TestCase
  def test_01_helper_test
    puts template_gemspec(:development_dependencies => %w[hoe rdoc])
    puts template_gemspec(:test_files => %w[test/test_file_1.rb test/test_file_2.rb])
    puts install_stub_gem(:test_files => [])
  end
end
