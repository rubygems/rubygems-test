Gem.autoload(:VersionOption, 'rubygems/version_option')
Gem.autoload(:Specification, 'rubygems/specification')
Gem.autoload(:DefaultUserInteraction, 'rubygems/user_interaction')
Gem.autoload(:DependencyInstaller, 'rubygems/dependency_installer')
require 'rbconfig'
autoload(:YAML, 'yaml')
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
    "#{program_name} GEM [-v VERSION] [--force] [--dep-user-install]"
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

    add_option(
      '--force', 
      'ignore opt-in testing and just run the tests'
    ) do |v,o| 
      o[:force] = true 
    end

    add_option(
      '--dep-user-install', 
      'force installing the dependencies into the user path'
    ) do |v,o| 
      o[:dep_user_install] = true 
    end
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
    begin
      rake_path = Gem.bin_path('rake') 
    rescue
      unless RUBY_VERSION > '1.9'
        alert_error "Couldn't find rake; rubygems-test will not work without it. Aborting."
        raise Gem::RakeNotFoundError, "Couldn't find rake; rubygems-test will not work without it."
      end
    end

    if RUBY_VERSION > '1.9'
      if RUBY_PLATFORM =~ /mswin/
        #
        # XXX GarbageCollect breaks ruby -S with rake.
        #
        return File.join(RbConfig::CONFIG["bindir"], 'rake.bat')
      else
        return rake_path || 'rake'
      end
    else
      return rake_path
    end
  end

  #
  # Install development dependencies for the gem we're about to test.
  #
  def install_dependencies(spec)
    di = nil

    if options[:dep_user_install]
      di = Gem::DependencyInstaller.new(:install_dir => Gem.user_dir)
    else
      di = Gem::DependencyInstaller.new
    end

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
        if body[:success]
          url = body[:data][0] if body[:data]
          say "Test results posted successfully! \n\t#{url}"
        else
          body[:errors].each do |error|
            say error
          end if body[:errors]
        end
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
  # Inner loop for platform_reader
  #
  def read_output(stdout, stderr)
    output = ""

    while ![stdout, stderr].reject(&:eof?).empty?
      handles, _, _ = IO.select([stdout, stderr].reject(&:eof?), nil, nil, 0.1)

      if handles
        if handles.include?(stderr)
          begin
            tmp_output = stderr.readline
            puts tmp_output
            output += tmp_output
          rescue EOFError
          end
        end

        if handles.include?(stdout)
          begin
            # 
            # readpartial seems to break on win32-open3's gem
            #
            if RUBY_PLATFORM =~ /mswin|mingw/ and RUBY_VERSION =~ /^1.8/
              tmp_output = "" 
              while IO.select([stdout], nil, nil, 0.1)
                tmp = stdout.read(1)
                if tmp
                  tmp_output += tmp
                else
                  break
                end
              end
            else
              tmp_output = stdout.readpartial(16384)
            end
            print tmp_output
            output += tmp_output
          rescue EOFError 
            #
            # This is another fix for readpartial wierdness on windows.
            # EOFError is sometimes raised when the fd still has data.
            #
            tmp_output ||= ""
            tmp_output += stdout.read rescue ""
            print tmp_output
            output += tmp_output
          end
        end
      end
    end

    return output
  end

  #
  # platform-specific reading routines.
  #
  def platform_reader(rake_args)
    # jruby stuffs it under IO, so we'll use that if it's available
    # if we're on 1.9, use open3 regardless of platform.
    # If we're not:
    #   * on windows use win32/open3 from win32-open3 gem
    #   * on unix use open4-vendor

    output, exit_status = nil, nil

    if IO.respond_to?(:popen4)
      IO.popen4(*rake_args) do |pid, stdin, stdout, stderr|
        output = read_output(stdout, stderr)
      end
      exit_status = $?
    elsif RUBY_VERSION > '1.9'
      require 'open3'
      exit_status = Open3.popen3(*rake_args) do |stdin, stdout, stderr, thr|
        output = read_output(stdout, stderr)
        thr.value
      end
    elsif RUBY_PLATFORM =~ /mingw|mswin/
      begin
        require 'win32/open3'
        Open3.popen3(*rake_args) do |stdin, stdout, stderr|
          output = read_output(stdout, stderr)
        end
        exit_status = $?
      rescue LoadError
        say "1.8/Windows users must install the 'win32-open3' gem to run tests"
        terminate_interaction 1
      end
    else
      require 'open4-vendor'
      exit_status = Open4.popen4(*rake_args) do |pid, stdin, stdout, stderr|
        output = read_output(stdout, stderr)
      end
    end

    return output, exit_status
  end

  #
  # obtain the rake arguments for a specific platform and environment.
  #
  def get_rake_args(rake_path, *args)
    if RUBY_PLATFORM =~ /mswin/
      #
      # XXX GarbageCollect breaks ruby -S with rake.
      #
     
      rake_args = [ rake_path ] + args
    else
      rake_args = [ Gem.ruby, '-rubygems', '-S' ] + [ rake_path, '--' ] + args
    end

    if RUBY_PLATFORM =~ /mswin|mingw/
      rake_args.join(' ')
    else
      rake_args
    end
  end

  #
  # Run the tests with the appropriate spec and rake_path, and capture all
  # output.
  #
  def run_tests(spec, rake_path)
    Dir.chdir(spec.full_gem_path) do
      rake_args = get_rake_args(rake_path, 'test', '--trace')

      output, exit_status = platform_reader(rake_args)

      if upload_results?
        upload_results(gather_results(spec, output, exit_status.exitstatus == 0))
      end

      if exit_status.exitstatus != 0
        alert_error "Tests did not pass. Examine the output and report it to the author!"

        raise Gem::TestError, "tests failed"
      end
    end
  end

  #
  # Convenience predicate for upload_results option
  #
  def upload_results?
    !options[:force] and (
      config["upload_results"] or
      (
        !config.has_key?("upload_results") and 
          ask_yes_no("Upload these results?", true)
      )
    )
  end
  

  #
  # Execute routine. This is where the magic happens.
  #
  def execute
    begin
      version = options[:version] || Gem::Requirement.default

      (get_all_gem_names rescue [options[:name]]).each do |name|

        unless name
          alert_error "No gem specified."
          show_help
          terminate_interaction 1
        end

        spec = find_gem(name, version)

        unless spec
          say "unable to find gem #{name} #{version}"
          next
        end

        if spec.files.include?('.gemtest') or options[:force]
          # we find rake and the rakefile first to eliminate needlessly installing
          # dependencies.
          find_rakefile(spec)
          rake_path = find_rake

          install_dependencies(spec)

          run_tests(spec, rake_path)
        else
          say "Gem '#{name}' (version #{version}) needs to opt-in for testing."
          say ""
          say "Locally available testing helps gems maintain high quality by"
          say "ensuring they work correctly on a wider array of platforms than the"
          say "original developer can access."
          say ""
          say "If you are the author: "
          say " * Add the file '.gemtest' to your spec.files"
          say " * Ensure 'rake test' works and doesn't do system damage"
          say " * Add your tests and Rakefile to your gem."
          say "" 
          say "For more information, please see the rubygems-test README:"
          say "https://github.com/rubygems/rubygems-test/blob/master/README.txt"
        end
      end
    rescue Gem::TestError
      raise if @on_install
      terminate_interaction 1
    end
  end
end
