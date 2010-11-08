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

  #--
  # FIXME fix the error messages.
  # FIXME refactor to not look like ass
  #++
  def execute
    version = options[:version] || Gem::Requirement.default

    gsi = Gem::SourceIndex.from_gems_in(*Gem::SourceIndex.installed_spec_directories)
    get_all_gem_names.each do |name|
      spec = gsi.find_name(name, version).last

      path = spec.full_gem_path
      rakefile = File.join(path, 'Rakefile')

      unless File.exist?(rakefile)
        alert_error "Couldn't find rakefile -- this gem cannot be tested." 
        terminate_interaction 1
      end

      rake_path = [Gem.bindir, Config::CONFIG["bindir"]].find { |x| File.exist?(File.join(x, "rake")) }

      unless rake_path
        alert_error "Couldn't find rake; rubygems-test will not work without it."
        terminate_interaction 1
      end

      FileUtils.chdir(path)

      config = Gem.configuration["test_options"] || { }

      di = Gem::DependencyInstaller.new

      spec.development_dependencies.each do |dep|
        unless gsi.search(dep).last
          if config["install_development_dependencies"]
            say "Installing test dependency #{dep.name} (#{dep.requirement})"
            di.install(dep) 
          else
            if ask_yes_no("Install development dependency #{dep.name} (#{dep.requirement})?")
              say "Installing test dependency #{dep.name} (#{dep.requirement})"
              di.install(dep) 
            else
              alert_error "Failed to install dependencies to test. Aborting."
              terminate_interaction 1
            end
          end
        end
      end

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
