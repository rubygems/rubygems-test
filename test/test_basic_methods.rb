require 'helper'

class TestBasicMethods < Test::Unit::TestCase
  def test_01_successfully_uninstalls_on_test_failure
    set_configuration({ "force_uninstall_on_failure" => true, "auto_test_on_install" => true })
    puts install_stub_gem(:test_files => [])
  end
end
