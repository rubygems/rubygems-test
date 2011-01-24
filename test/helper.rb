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

  def set_gem_temp_paths
    @gem_temp_path = Dir.mktmpdir('rubygems-test')
    @gem_home = Gem.dir
    @gem_paths = Gem.path
    Gem.clear_paths
    Gem.path.replace [@gem_temp_path]
    Gem.send :set_home, @gem_temp_path
    Gem.refresh
  end

  def unset_gem_temp_paths
    FileUtils.rm_rf @gem_temp_path if @gem_temp_path
    Gem.clear_paths

    #
    # XXX Yep, big WTF here.
    #
    if RUBY_PLATFORM =~ /java|mingw/
      Gem.path.replace @gem_paths
    else
      Gem.path.replace [@gem_paths]
    end
    Gem.send :set_home, @gem_home
    Gem.refresh
  end

  def setup
    set_configuration({ })
    set_gem_temp_paths
  end

  def teardown
    uninstall_stub_gem rescue nil
    unset_gem_temp_paths
  end
end
