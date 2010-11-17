require 'helper'
require 'rbconfig'
require 'yaml'

class TestExecute < Test::Unit::TestCase
  def setup
    super
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

  def test_06_find_rake
    # XXX how do I test this fully without nuking rake?
    assert_nothing_raised { @test.find_rake }
    assert_not_nil @test.find_rake
  end

  def test_07_gather_results
    install_stub_gem({})

    spec = @test.find_gem("test-gem", "0.0.0")
    output = <<-OUT
/home/josiah/.rvm/rubies/ruby-1.9.2-p0/bin/ruby -I"lib:lib:test" "/home/josiah/.rvm/rubies/ruby-1.9.2-p0/lib/ruby/1.9.1/rake/rake_test_loader.rb" "test/test_pass.rb" 
Loaded suite /home/josiah/.rvm/rubies/ruby-1.9.2-p0/lib/ruby/1.9.1/rake/rake_test_loader
Started
.
Finished in 0.000314 seconds.

1 tests, 1 assertions, 0 failures, 0 errors, 0 skips

OUT

    expected_output = <<-OUT
/home/$user/.rvm/rubies/ruby-1.9.2-p0/bin/ruby -I"lib:lib:test" "/home/$user/.rvm/rubies/ruby-1.9.2-p0/lib/ruby/1.9.1/rake/rake_test_loader.rb" "test/test_pass.rb" 
Loaded suite /home/$user/.rvm/rubies/ruby-1.9.2-p0/lib/ruby/1.9.1/rake/rake_test_loader
Started
.
Finished in 0.000314 seconds.

1 tests, 1 assertions, 0 failures, 0 errors, 0 skips

OUT

    hash = {
      :arch         => RbConfig::CONFIG["arch"],
      :vendor       => RbConfig::CONFIG["target_vendor"],
      :os           => RbConfig::CONFIG["target_os"],
      :machine_arch => RbConfig::CONFIG["target_cpu"],
      :ruby_version => RUBY_VERSION,
      :result       => true,
      :name         => spec.name,
      :version      => spec.version,
      :platform     => spec.platform,
      :test_output  => expected_output
    }


    assert_equal YAML.load(@test.gather_results(spec, output, true)), hash
  end
end
