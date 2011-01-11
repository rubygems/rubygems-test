require 'rubygems' unless defined? Gem
require 'rubygems/builder' unless defined? Gem::Builder
require 'rubygems/user_interaction' unless defined? Gem::UserInteraction
require 'rubygems/installer' unless defined? Gem::Installer
require 'rubygems/uninstaller' unless defined? Gem::Uninstaller
require 'test/unit'
require 'erb'
require 'tempfile'
require 'fileutils'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'rubygems/commands/test_command' unless defined? Gem::Command::TestCommand

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

  def teardown
    uninstall_stub_gem rescue nil
  end
end
