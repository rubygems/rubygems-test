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

      if File.exists?(rakefile)

        $stderr.puts "Rakefile found: #{rakefile}"

        rake_path = [Gem.bindir, Config::CONFIG["bindir"]].find { |x| File.exists?(File.join(x, "rake")) }

        if rake_path

          FileUtils.chdir(path)

          config = Gem.configuration["test_options"] || { }
         
            di = Gem::DependencyInstaller.new

            spec.development_dependencies.each do |dep|
              unless gsi.search(dep).last
                if config["install_development_dependencies"]
                  puts "Installing test dependency #{dep.name} (#{dep.requirement})"
                  di.install(dep) 
                else
                  if ui.ask_yes_no("Install development dependency #{dep.name} (#{dep.requirement})?")
                    puts "Installing test dependency #{dep.name} (#{dep.requirement})"
                    di.install(dep) 
                  else
                    throw "Failed to install dependencies to test. Aborting."
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
            throw "Tests did not pass. Examine output, yo!"
          end
        else
          throw "Couldn't find rake. Check yo' self foo." 
        end

      else
        throw "can't find rakefile"
      end
    end
  end
end
