# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.plugins.delete :rubyforge
Hoe.plugin :git

Hoe.spec 'rubygems-test' do
  developer 'Erik Hollensbe', 'erik@hollensbe.org'
  developer 'Josiah Kiehl', 'bluepojo@gmail.com'

  # doin' it wrong because we're a gem plugin
  # that means I can be "special"!
 
  self.rubyforge_name = nil
  self.version = '0.1.9'
  self.description = <<-EOF
  This installs three major features:

  * a 'gem test' command.
  * the ability to test your gems on installation, and uninstall them if they fail testing.
  * A facility to upload your test results to rubygems.org (coming soon, see http://github.com/bluepojo/gem-testers)
  EOF
  self.summary = 'commands and facilities for automated rubygems testing and reporting'
  self.url = %w[http://github.com/rubygems/rubygems-test]
  
  require_ruby_version ">= 1.8.7"
  pluggable!

  extra_deps << ['rake', '>= 0.8.7']

  desc "install a gem without sudo"
  task :install => [:gem] do
    sh "gem install pkg/#{self.name}-#{self.version}.gem"
  end
end

# vim: syntax=ruby
