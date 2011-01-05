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
  
  self.version = '0.1.9'
  
  require_ruby_version     ">= 1.8.7"
  require_rubygems_version ">= 1.3.6"

  extra_deps << ['rake', '>= 0.8.7']

  desc "install a gem without sudo"
  task :install => [:gem] do
    sh "gem install pkg/#{self.name}-#{self.version}.gem"
  end
end

# vim: syntax=ruby
