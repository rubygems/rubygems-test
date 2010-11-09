require 'rubygems'
require 'rubygems/commands/test_command'

Gem.post_install do |gem|
  options = Gem.configuration["test_options"]
  if options["auto_test_on_install"] or options["test_on_install"]
    if options["auto_test_on_install"] or
        gem.ui.ask_yes_no "Test #{gem.spec.name} (#{gem.spec.version})? "
      Gem::Commands::TestCommand.new(gem.spec).execute
    end
  end
end
