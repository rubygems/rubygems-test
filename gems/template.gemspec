Gem::Specification.new do |s|
  s.name = "test-gem"
  s.version = "0.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Erik Hollensbe"]
  s.date = %q{2010-11-12}
  s.description = "GEM_TEST_DESCRIPTION"
  s.email = %q{erik@hollensbe.org}
  s.files = [
    <%= @files %>
  ].flatten
  s.homepage = %q{http://example.org}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Gem testing facility as a plugin}
  s.rubyforge_project = %q[foo]

  <%= @development_dependencies %>

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3
  end
end
