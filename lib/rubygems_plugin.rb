require 'rubygems/command_manager'

# shamelessly taken from gemcutter.

if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.3.6')
  %w[test].each do |command|
    Gem::CommandManager.instance.register_command command.to_sym
  end
end
