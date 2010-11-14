require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "rubygems-test"
    gem.summary = %Q{Gem testing facility as a plugin}
    gem.description = %Q{Test gems on your system, upload the data to a service. Uninstall failing gems.}
    gem.email = "erik@hollensbe.org"
    gem.homepage = "http://github.com/erikh/rubygems-test"
    gem.authors = ["Erik Hollensbe", "Josiah Kiehl"]
    gem.files = Dir["Rakefile"] + Dir["lib/**/*.rb"] + Dir["test/**/*.rb"]
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
    #
    gem.add_dependency 'rake'
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:gemtest) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = Dir["test/test_*.rb"]
  test.verbose = true
end

Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = Dir["test/test_*.rb"] + Dir["test/interactive_test_*.rb"]
  test.verbose = true
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/test_*.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
  end
end

task :test => :check_dependencies

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "rubygems-test #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
