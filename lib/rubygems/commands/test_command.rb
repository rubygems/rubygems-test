Gem.autoload(:VersionOption, 'rubygems/version_option')
Gem.autoload(:Specification, 'rubygems/specification')
Gem.autoload(:DefaultUserInteraction, 'rubygems/user_interaction')
Gem.autoload(:DependencyInstaller, 'rubygems/dependency_installer')
Gem.autoload(:RakeNotFoundError, 'exceptions')
Gem.autoload(:TestError, 'exceptions')
Gem.autoload(:Installer, 'rubygems/installer')
require 'rbconfig'
autoload(:YAML, 'yaml')
require 'net/http'
require 'uri'

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
    rake_path = nil;

    begin
      rake_path = Gem.bin_path('rake') 
    rescue
      if RUBY_VERSION > '1.9' and File.exist?(File.join(RbConfig::CONFIG["bindir"], Gem::Installer.exec_format % 'rake'))
        rake_path = File.join(RbConfig::CONFIG["bindir"], Gem::Installer.exec_format % 'rake')
      else
        alert_error "Couldn't find rake; rubygems-test will not work without it. Aborting."
        raise Gem::RakeNotFoundError, "Couldn't find rake; rubygems-test will not work without it."
      end
    end

    if RUBY_VERSION > '1.9' and !rake_path
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

    $RG_T_INSTALLING_DEPENDENCIES = true
    spec.development_dependencies.each do |dep|
      unless Gem.source_index.search(dep).last
        if config["install_development_dependencies"] || Gem.configuration.verbose == false
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
    $RG_T_INSTALLING_DEPENDENCIES = false
    true
  end

  ##
  # Normalize the URI by adding "http://" if it is missing.
  #
  #--
  #
  # taken verbatim from rubygems.
  #

  def normalize_uri(uri)
    (uri =~ /^(https?|ftp|file):/) ? uri : "http://#{uri}"
  end
 
  ##
  # Escapes a URI.
  #
  #--
  #
  # Taken verbatim from rubygems.
  #
  def escape(str)
    return nil unless str
    URI.escape str
  end

  # 
  # if a proxy is supplied, return a URI
  # 
  #--
  #
  # taken almost verbatim from rubygems.
  #
  def proxy
    env_proxy = ENV['http_proxy'] || ENV['HTTP_PROXY']

    return nil if env_proxy.nil? or env_proxy.empty?

    uri = URI.parse(normalize_uri(env_proxy))

    if uri and uri.user.nil? and uri.password.nil? then
      # Probably we have http_proxy_* variables?
      uri.user = escape(ENV['http_proxy_user'] || ENV['HTTP_PROXY_USER'])
      uri.password = escape(ENV['http_proxy_pass'] || ENV['HTTP_PROXY_PASS'])
    end

    uri
  end
 
  #
  # Upload +yaml+ Results to +results_url+.
  #

  def upload_results(yaml, results_url=nil)
    begin
      results_url ||= config["upload_service_url"] || 'http://test.rubygems.org/test_results' 
      url = URI.parse(results_url)

      net_http_args = [url.host, url.port]

      if proxy_uri = proxy
        net_http_args += [
          proxy_uri.host,
          proxy_uri.port,
          proxy_uri.user,
          proxy_uri.password
        ]
      end

      http = Net::HTTP.new(*net_http_args)

      if ENV["RG_T_DEBUG_HTTP"]
        http.set_debug_output($stderr)
      end

      req = Net::HTTP::Post.new(url.path)
      req.set_form_data({:results => yaml})
      response = http.start { |x| x.request(req) }

      case response
      when Net::HTTPSuccess
        body = YAML::load(response.body)
        if body[:success]
          url = body[:data][0] if body[:data]
          say "\nTest results posted successfully! \n\nresults url:\t#{url}\n\n"
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
    rescue Errno::ECONNREFUSED => e
      say 'Unable to post test results. Can\'t connect to the results server.'
    rescue => e
      say e.message
      say e.backtrace
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
        :release      => spec.version.to_s,
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
    require 'thread'

    STDOUT.sync = true
    STDERR.sync = true
    stdout.sync = true
    stderr.sync = true

    output = ""
    mutex = Mutex.new

    err_t = Thread.new do
      while !stderr.eof?
        tmp = stderr.readline
        mutex.synchronize do
          output << tmp
          print tmp
        end
      end
    end

    out_t = Thread.new do
      while !stdout.eof?
        tmp = stdout.read(1)
        mutex.synchronize do
          output << tmp
          print tmp
        end
      end
    end

    while !stderr.eof? or !stdout.eof?
      Thread.pass
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

    output, exit_status = *[]

    if IO.respond_to?(:popen4)
      IO.popen4(*rake_args) do |pid, stdin, stdout, stderr|
        output = read_output(stdout, stderr)
      end
      exit_status = $?
    elsif RUBY_VERSION > '1.9'
      require 'open3'
      Open3.popen3(*rake_args) do |stdin, stdout, stderr, thr|
        output = read_output(stdout, stderr)
        exit_status = thr.value
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
    if RUBY_PLATFORM =~ /mswin/ and RUBY_VERSION > '1.9'
      #
      # XXX GarbageCollect breaks ruby -S with rake on 1.9.
      #
     
      rake_args = [ rake_path ] + args
    else
      rake_args = [ Gem.ruby, '-rubygems', '-S' ] + [ rake_path, '--' ] + args
    end

    if RUBY_PLATFORM =~ /mswin|mingw/
      # we don't use shellwords for the rest because they use execve().
      require 'shellwords'
      rake_args.map { |x| Shellwords.shellescape(x) }.join(' ')
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
      rake_args = get_rake_args(rake_path, 'test')

      @trapped = false
      ::Kernel.trap("INT") { @trapped = true } 

      output, exit_status = platform_reader(rake_args)

      ::Kernel.trap("INT", "DEFAULT")

      if !@trapped and upload_results?
        upload_results(gather_results(spec, output, exit_status.exitstatus == 0))
      end

      if exit_status.exitstatus != 0
        if @trapped
          alert_error "You interrupted the test! Test runs are not valid unless you let them complete!"
        else
          alert_error "Tests did not pass. Examine the output and report it to the author!"
        end

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
        Gem.configuration.verbose == false ||
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

        if File.exist?(File.join(spec.installation_path, '.gemtest')) or options[:force]
          # we find rake and the rakefile first to eliminate needlessly installing
          # dependencies.
          find_rakefile(spec)
          rake_path = find_rake

          unless $RG_T_INSTALLING_DEPENDENCIES and !config["test_development_dependencies"]
            install_dependencies(spec)
            run_tests(spec, rake_path)
          end
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
