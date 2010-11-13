require 'helper'

class TestRubyGemsOnInstallTest < Test::Unit::TestCase

  def setup
    super
    puts
    puts "----- This test is interactive -----"
    puts
  end

  def test_01_successfully_uninstalls_on_test_failure
    set_configuration({ "force_uninstall_on_failure" => true, "auto_test_on_install" => true })
    install_stub_gem(:files => [])
  end

  def test_02_successfully_installs_on_test_pass
    set_configuration({ "auto_test_on_install" => true, "upload_results" => false })
    install_stub_gem(:files => %w[test/test_pass.rb Rakefile])
  end
end
