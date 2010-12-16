require 'rubygems/version_option'
require 'rubygems/source_index'
require 'rubygems/specification'
require 'rubygems/dependency_installer'
require 'rubygems/user_interaction'
require 'fileutils'
require 'pathname'
require 'rbconfig'
require 'yaml'
require 'open3'
require 'net/http'
require 'uri'
require 'ostruct'

class Gem::TestError < Gem::Exception; end
class Gem::RakeNotFoundError < Gem::Exception; end

class Gem::Commands::TestCommand < Gem::Command
  include Gem::VersionOption
  include Gem::DefaultUserInteraction

  # taken straight out of rake
  DEFAULT_RAKEFILES = ['rakefile', 'Rakefile', 'rakefile.rb', 'Rakefile.rb'].freeze

  def description
    'Run the tests for a specific gem'
  end

  def arguments
    "GEM: name of gem"
  end
  
  def usage
    "#{program_name} GEM -v VERSION"
  end
  
  def initialize(spec=nil, on_install=false)
    options = { } 

    if spec
      options[:name] = spec.name
      options[:version] = spec.version
    end

    @on_install = on_install

    super 'test', description, options
    add_version_option
  end

  #
  # Retrieve the source index
  #
  def source_index 
    @gsi = Gem::SourceIndex.from_gems_in(*Gem::SourceIndex.installed_spec_directories)
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
    unless spec and (spec.installation_path rescue nil)
      alert_error "Could not find gem #{name} (#{version})"
      raise Gem::GemNotFoundException, "Could not find gem #{name}, (#{version})"
    end

    return spec
  end

  #
  # Locate the rakefile for a gem name and version
  #
  def find_rakefile(spec)
    rakefile = DEFAULT_RAKEFILES.
      map  { |x| File.join(spec.full_gem_path, x) }.
      find { |x| File.exist?(x) }

    unless(File.exist?(rakefile) rescue nil)
      alert_error "Couldn't find rakefile -- this gem cannot be tested. Aborting." 
      raise Gem::RakeNotFoundError, "Couldn't find rakefile, gem #{spec.name} (#{spec.version}) cannot be tested."
    end
  end

  #
  # Locate rake itself, prefer gems version.
  #
  def find_rake
    rake_path = Gem.bin_path('rake') rescue File.join(RbConfig::CONFIG["bindir"], 'rake')

    unless File.exist?(rake_path)
      alert_error "Couldn't find rake; rubygems-test will not work without it. Aborting."
      raise Gem::RakeNotFoundError, "Couldn't find rake; rubygems-test will not work without it."
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
          if ask_yes_no("Install development dependency #{dep.name} (#{dep.requirement})?", true)
            say "Installing test dependency #{dep.name} (#{dep.requirement})"
            di.install(dep) 
          else
            alert_error "Failed to install dependencies required to run tests. Aborting."
            raise Gem::TestError
          end
        end
      end
    end
  end
 
  #
  # Upload +yaml+ Results to +results_url+.
  #

  def upload_results(yaml)
    begin
      results_url = config["upload_service_url"] || 'http://gem-testers.org/test_results' 
      url = URI.parse(results_url)
      response = Net::HTTP.post_form url, {:results => yaml}
    rescue Errno::ECONNREFUSED => e
      say 'Unable to post test results. Can\'t connect to the results server.'
    rescue => e
      say e.message
    else
      case response
      when Net::HTTPSuccess
        body = YAML::load(response.body)
        url = body[:data][0] if body[:data]
        say "Test results posted successfully! \n\t#{url}"
      when Net::HTTPRedirection
        upload_results yaml, response.fetch('Location')
      when Net::HTTPNotFound
        say %q[Unable to find where to put the test results. Try: `gem update rubygems-test`]
      when Net::HTTPClientError
        say %q[Results server didn't like the results submission. Try: `gem update rubygems-test`]
      when Net::HTTPServerError
        say %q[Oof. Something went wrong on the results server processing these results. Sorry!]
      else
        say %q[Something weird happened. Probably a bug.]
      end
    end
  end

  #
  # Gather system results, test results into a YAML format ready for delivery.
  #
  def gather_results(spec, output, result)
    {
      :arch         => RbConfig::CONFIG["arch"],
      :vendor       => RbConfig::CONFIG["target_vendor"],
      :os           => RbConfig::CONFIG["target_os"],
      :machine_arch => RbConfig::CONFIG["target_cpu"],
      :name         => spec.name,
      :version      => spec.version,
      :platform     => spec.platform,
      :ruby_version => RUBY_VERSION,
      :result       => result,
      :test_output  => output
    }.to_yaml
  end


  #
  # Run the tests with the appropriate spec and rake_path, and capture all
  # output.
  #
  def run_tests(spec, rake_path)
    pwd = FileUtils.pwd

    FileUtils.chdir(spec.full_gem_path)

    output = ""
    exit_status = nil

    if spec.files.include?(".gemtest")
      open_proc = proc do |stdin, stdout, stderr, thr|
        loop do
          if stdout.eof? and stderr.eof?
            break
          end

          buf = ""

          handles, _, _ = IO.select([stdout, stderr].reject { |x| x.closed? || x.eof? }, nil, nil, 0.1)

          begin
            handles.each { |io| io.readpartial(16384, buf) } if handles
          rescue EOFError, IOError
            next
          end

          output += buf

          print buf
        end

        unless RUBY_VERSION =~ /^1.8/
          exit_status = thr.value
        end
      end

      if RUBY_VERSION =~ /^1.8/
        Open3.popen3(rake_path, "test", '--trace', &open_proc) 
        exit_status = $?
      else
        Open3.popen3(rake_path, "test", '--trace', &open_proc) 
      end

      if config["upload_results"] or
        (!config.has_key?("upload_results") and ask_yes_no("Upload these results to rubygems.org?", true))

        upload_results(gather_results(spec, output, exit_status.exitstatus == 0))
      end

      if exit_status.exitstatus != 0
        alert_error "Tests did not pass. Examine the output and report it to the author!"

        FileUtils.chdir(pwd)

        raise Gem::TestError
      end
    else
      alert_warning "This gem has no tests! Please contact the author to gain testing and reporting!"
    end

    FileUtils.chdir(pwd)
  end

  #
  # Execute routine. This is where the magic happens.
  #
  def execute
    begin
      version = options[:version] || Gem::Requirement.default

      (get_all_gem_names rescue [options[:name]]).each do |name|
        spec = find_gem(name, version)

        if spec.files.include?('.gemtest')
          # we find rake and the rakefile first to eliminate needlessly installing
          # dependencies.
          find_rakefile(spec)
          rake_path = find_rake

          install_dependencies(spec)

          run_tests(spec, rake_path)
        end
      end
    rescue Exception => e 
      if @on_install
        raise e
      else
        terminate_interaction 1
      end
    end
  end
end
