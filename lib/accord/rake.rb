# frozen_string_literal: true

# Load Accord's rake tasks outside Rails: `require "accord/rake"` in a Rakefile.
# (Under Rails the Railtie loads them automatically.) Make sure your schemas are
# required before running `accord:rbs`, since discovery walks loaded subclasses.
load File.expand_path("tasks/accord.rake", __dir__)
