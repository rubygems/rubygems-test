require 'rubygems/version_option'
require 'rubygems/source_index'
require 'rubygems/specification'

class Gem::Commands::TestCommand < Gem::Command
  include Gem::VersionOption

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

  def execute
    version = options[:version] || Gem::Requirement.default

    gsi = Gem::SourceIndex.from_gems_in(*Gem::SourceIndex.installed_spec_directories)
    get_all_gem_names.each do |name|
      spec = gsi.find_name(name, version).last
      rakefile = File.join(spec.full_gem_path, 'Rakefile')
      if File.exists?(rakefile)
        $stderr.puts "Rakefile found: #{rakefile}"
        require 'rbconfig'
        rake_path = [Gem.bindir, Config::CONFIG["bindir"]].find { |x| File.exists?(File.join(x, "rake")) }

        if rake_path
          require 'fileutils'

          pwd = FileUtils.pwd
          FileUtils.chdir(spec.full_gem_path)

          system(File.join(rake_path, "rake"), 'gemtest')
          if $?.exitstatus != 0
            throw "Tests did not pass. Examine output, yo!"
          end
        else
          throw "Couldn't find rake. Check yo' self foo." 
        end
      else
        # FIXME you sure got a purty mouth
        throw "can't find rakefile"
      end
    end
  end
end
