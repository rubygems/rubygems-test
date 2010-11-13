# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run the gemspec command
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{rubygems-test}
  s.version = "0.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Erik Hollensbe"]
  s.date = %q{2010-11-13}
  s.description = %q{Test gems on your system. Conform to a spec where awesomeness occurs. Edit this later.}
  s.email = %q{erik@hollensbe.org}
  s.extra_rdoc_files = [
    "LICENSE",
     "README.rdoc"
  ]
  s.files = [
    "Rakefile",
     "lib/rubygems/commands/test_command.rb",
     "lib/rubygems/on_install_test.rb",
     "lib/rubygems_plugin.rb",
     "test/helper.rb",
     "test/test_command_test.rb"
  ]
  s.homepage = %q{http://github.com/erikh/rubygems-test}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Gem testing facility as a plugin}
  s.test_files = [
    "test/test_command_test.rb",
     "test/helper.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end

