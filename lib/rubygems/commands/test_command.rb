require 'rubygems/version_option'
require 'rubygems/specification'
require 'rubygems/dependency_installer'
require 'rubygems/user_interaction'
require 'rbconfig'
require 'yaml'
require 'net/http'
require 'uri'

class Gem::TestError < Gem::Exception; end
class Gem::RakeNotFoundError < Gem::Exception; end

class Gem::Commands::TestCommand < Gem::Command
  include Gem::VersionOption
  include Gem::DefaultUserInteraction

  # taken straight out of rake
  DEFAULT_RAKEFILES = ['rakefile', 'Rakefile', 'rakefile.rb', 'Rakefile.rb']

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
  # Get the config in our namespace
  #
  def config 
    @config ||= Gem.configuration["test_options"] || { }
  end

  #
  # find a gem given a name and version
  #
  def find_gem(name, version)
    spec = Gem.source_index.find_name(name, version).last
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
      unless Gem.source_index.search(dep).last
        if config["install_development_dependencies"]
          say "Installing test dependency #{dep.name} (#{dep.requirement})"
          di.install(dep) 
        else
          if ask_yes_no("Install development dependency #{dep.name} (#{dep.requirement})?", true)
            say "Installing test dependency #{dep.name} (#{dep.requirement})"
            di.install(dep) 
          else
            alert_error "Failed to install dependencies required to run tests. Aborting."
            raise Gem::TestError, "dependencies not installed"
          end
        end
      end
    end
  end
 
  #
  # Upload +yaml+ Results to +results_url+.
  #

  def upload_results(yaml, results_url=nil)
    begin
      results_url ||= config["upload_service_url"] || 'http://gem-testers.org/test_results' 
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
        location = response.fetch('Location')
        if !location or URI.parse(location) == url
          say %[Caught redirection but was unable to redirect to #{location}.]
        else
          upload_results yaml, location 
        end
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
      :version      => {
        :release      => spec.version.release.to_s,
        :prerelease   => spec.version.prerelease?
      },
      :platform     => (Kernel.const_get("RUBY_ENGINE") rescue "ruby"),
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
    output = ""
    exit_status = nil

    Dir.chdir(spec.full_gem_path) do

      if spec.files.include?(".gemtest")
        reader_proc = proc do |orig_handles|
          current_handles = orig_handles.dup

          handles, _, _ = IO.select(current_handles, nil, nil, 0.1)
          buf = ""

          handles.each do |io| 
            begin
              io.readpartial(16384, buf)
            rescue EOFError
              buf += io.read rescue ""
              current_handles.reject! { |x| x == io }
            rescue IOError
              current_handles.reject! { |x| x == io }
            end
          end if handles

          [buf, current_handles]
        end

        outer_reader_proc = proc do |stdout, stderr|
          loop do
            handles = [stdout, stderr]
            buf, handles = reader_proc.call(handles) 
            output += buf
            print buf
            break if handles.empty?
          end
        end

        # jruby stuffs it under IO, so we'll use that if it's available
        klass = 
          if IO.respond_to?(:popen4)
            IO.popen4(rake_path, 'test', '--trace') do |pid, stdin, stdout, stderr|
              outer_reader_proc.call(stdout, stderr)
            end
            exit_status = $?
          elsif RUBY_VERSION > '1.9'
            require 'open3'
            exit_status = Open3.popen3(rake_path, 'test', '--trace') do |stdin, stdout, stderr, thr|
              outer_reader_proc.call(stdout, stderr)
              thr.value
            end
          else
            require 'open4-vendor'
            exit_status = Open4.popen4(rake_path, 'test', '--trace') do |pid, stdin, stdout, stderr|
              outer_reader_proc.call(stdout, stderr)
            end
          end


        if config["upload_results"] or
          (!config.has_key?("upload_results") and ask_yes_no("Upload these results to rubygems.org?", true))

          upload_results(gather_results(spec, output, exit_status.exitstatus == 0))
        end

        if exit_status.exitstatus != 0
          alert_error "Tests did not pass. Examine the output and report it to the author!"

          raise Gem::TestError, "tests failed"
        end
      else
        alert_warning "This gem has no tests! Please contact the author to gain testing and reporting!"
      end
    end
  end

  #
  # Execute routine. This is where the magic happens.
  #
  def execute
    begin
      version = options[:version] || Gem::Requirement.default

      (get_all_gem_names rescue [options[:name]]).each do |name|
        spec = find_gem(name, version)

        unless spec
          say "unable to find gem #{name} #{version}"
          next
        end

        if spec.files.include?('.gemtest')
          # we find rake and the rakefile first to eliminate needlessly installing
          # dependencies.
          find_rakefile(spec)
          rake_path = find_rake

          install_dependencies(spec)

          run_tests(spec, rake_path)
        end
      end
    rescue Gem::TestError
      raise if @on_install
      terminate_interaction 1
    end
  end
end
