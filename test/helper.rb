require 'rubygems'
require 'rubygems/builder'
require 'rubygems/installer'
require 'rubygems/uninstaller'
require 'test/unit'
require 'erb'
require 'tempfile'
require 'fileutils'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'rubygems/commands/test_command'

class Test::Unit::TestCase
  def install_stub_gem(hash)
    file = Tempfile.new("rubygems-test")
    file.write(template_gemspec(hash))
    path = file.path
    file.close

    FileUtils.chdir('gems') do
      spec = eval File.read(path)
      filename = Gem::Builder.new(spec).build
      Gem::Installer.new(filename).install
      Gem.refresh
    end
  end

  def uninstall_stub_gem
    Gem::Uninstaller.new("test-gem").uninstall
    Gem.refresh
  end

  def template_gemspec(hash)
    erb = ERB.new(File.read(File.join('gems', 'template.gemspec')))

    @development_dependencies = ""
    (hash[:development_dependencies] || []).each do |dep|
      @development_dependencies += "s.add_development_dependency '#{dep}'\n"
    end

    @files = hash[:files] || "'Rakefile', Dir['test/**/*']"

    if @files.kind_of?(Array)
      @files = @files.map { |x| "'#{x}'" }.join(",\n")
    end

    return erb.result(binding)
  end

  def set_configuration(hash)
    Gem.configuration["test_options"] = hash
    Gem.configuration.verbose = false
  end

  def setup
    set_configuration({ })
  end
end

class Test::Unit::TestCase::Interactive < Test::Unit::TestCase
  def setup
    super

    require 'rubygems/on_install_test'
    puts
    puts "----- This test is interactive -----"
    puts
  end

  def test_01_null
  end
end
