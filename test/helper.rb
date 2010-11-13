require 'rubygems'
require 'rubygems/builder'
require 'rubygems/installer'
require 'test/unit'
require 'erb'
require 'tempfile'
require 'fileutils'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'rubygems/on_install_test'
require 'rubygems/commands/test_command'

class Test::Unit::TestCase
  def install_stub_gem(hash)
    file = Tempfile.new("rubygems-test")
    file.write(template_gemspec(hash))
    path = file.path
    file.close

    pwd = FileUtils.pwd
    FileUtils.chdir('gems')

    spec = eval File.read(path)
    filename = Gem::Builder.new(spec).build
    Gem::Installer.new(filename).install
  end

  def template_gemspec(hash)
    erb = ERB.new(File.read(File.join('gems', 'template.gemspec')))

    @development_dependencies = ""
    (hash[:development_dependencies] || []).each do |dep|
      @development_dependencies += "s.add_development_dependency '#{dep}'\n"
    end

    @files = hash[:test_files] || "'Rakefile', Dir['test/**/*']"

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
