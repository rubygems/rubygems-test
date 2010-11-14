require 'helper'

class TestExecute < Test::Unit::TestCase
  def setup
    set_configuration({ })
    @test = Gem::Commands::TestCommand.new
  end

  def test_01_config
    set_configuration({ "auto_test_on_install" => true })
    assert @test.config
    assert @test.config.has_key?("auto_test_on_install")
    assert @test.config["auto_test_on_install"]
  end

  def test_02_gem_command_attributes
    assert_equal @test.description, "Run the tests for a specific gem"
    assert_equal @test.arguments, "GEM: name of gem"
    assert_equal @test.usage, "#{@test.program_name} GEM -v VERSION"
  end

  def test_03_source_index
    install_stub_gem({ })

    assert @test.source_index
    assert_kind_of Array, @test.source_index.find_name("test-gem", Gem::Version.new("0.0.0"))
    assert_kind_of Gem::Specification, @test.source_index.find_name("test-gem", Gem::Version.new("0.0.0")).last

    uninstall_stub_gem
  end

  def test_04_find_gem
    install_stub_gem({ })

    assert_kind_of Gem::Specification, @test.find_gem("test-gem", "0.0.0")

    uninstall_stub_gem

    assert_raises(Gem::GemNotFoundException) { @test.find_gem("test-gem", "0.0.0") }
  end

  def test_05_find_rakefile
    install_stub_gem({ :files => ["Rakefile"] })

    assert_nothing_raised { @test.find_rakefile(@test.find_gem("test-gem", "0.0.0")) }

    uninstall_stub_gem
    install_stub_gem({ :files => "" })

    assert_raises(Gem::RakeNotFoundError) { @test.find_rakefile(@test.find_gem("test-gem", "0.0.0")) }

    uninstall_stub_gem
  end
end
