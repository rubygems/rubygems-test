require 'rubygems/version_option'
require 'rubygems/source_index'
require 'rubygems/specification'
require 'rubygems/dependency_installer'
require 'rubygems/user_interaction'
require 'fileutils'
require 'rbconfig'

class Gem::Commands::TestCommand < Gem::Command
  include Gem::VersionOption
  include Gem::DefaultUserInteraction

  def description
    'Run the tests for a specific gem'
  end

  def arguments
    "GEM: name of gem"
  end
  
  def usage
    "#{program_name} GEM -v VERSION"
  end
  
  def initialize
    super 'test', description
    add_version_option
  end

  #
  # Retrieve the source index
  #
  def source_index 
    @gsi ||= Gem::SourceIndex.from_gems_in(*Gem::SourceIndex.installed_spec_directories)
  end
 
  #
  # Get the config in our namespace
  #
  def config 
    @config ||= Gem.configuration["test_options"] || { }
  end

  #
  # find a gem given a name and version
  #
  def find_gem(name, version)
    spec = source_index.find_name(name, version).last
    unless spec
      alert_error "Could not find gem #{name} (#{version})"
      terminate_interaction 1
    end

    return spec
  end

  #
  # Locate the rakefile for a gem name and version
  #
  def find_rakefile(spec)
    rakefile = File.join(spec.full_gem_path, 'Rakefile')

    unless File.exist?(rakefile)
      alert_error "Couldn't find rakefile -- this gem cannot be tested. Aborting." 
      terminate_interaction 1
    end
  end

  #
  # Locate rake itself, prefer gems version.
  #
  def find_rake
    rake_path = [Gem.bindir, Config::CONFIG["bindir"]].find { |x| File.exist?(File.join(x, "rake")) }

    unless rake_path
      alert_error "Couldn't find rake; rubygems-test will not work without it. Aborting."
      terminate_interaction 1
    end

    return rake_path
  end

  #
  # Install development dependencies for the gem we're about to test.
  #
  def install_dependencies(spec)
    di = Gem::DependencyInstaller.new

    spec.development_dependencies.each do |dep|
      unless source_index.search(dep).last
        if config["install_development_dependencies"]
          say "Installing test dependency #{dep.name} (#{dep.requirement})"
          di.install(dep) 
        else
          if ask_yes_no("Install development dependency #{dep.name} (#{dep.requirement})?")
            say "Installing test dependency #{dep.name} (#{dep.requirement})"
            di.install(dep) 
          else
            alert_error "Failed to install dependencies required to run tests. Aborting."
            terminate_interaction 1
          end
        end
      end
    end
  end

  #
  # Execute routine. This is where the magic happens.
  #
  def execute
    version = options[:version] || Gem::Requirement.default

    get_all_gem_names.each do |name|
      spec = find_gem(name, version)

      # we find rake and the rakefile first to eliminate needlessly installing
      # dependencies.
      find_rakefile(spec)
      rake_path = find_rake

      install_dependencies(spec)
      
      FileUtils.chdir(spec.full_gem_path)

      if config["use_rake_test"]
        system(File.join(rake_path, "rake"), 'test')
      else
        system(File.join(rake_path, "rake"), 'gemtest')
      end

      if $?.exitstatus != 0
        alert_error "Tests did not pass. Examine the output and report it to the author!"
        terminate_interaction 1
      end
    end
  end
end
