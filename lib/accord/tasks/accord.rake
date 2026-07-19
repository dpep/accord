# frozen_string_literal: true

require "accord"

namespace :accord do
  desc "Export RBS signatures for every declared Accord schema (OUTPUT=sig/accord.rbs)"
  task :rbs do
    # Ensure the app (and its schemas) are loaded before discovery.
    Rake::Task["environment"].invoke if Rake::Task.task_defined?("environment")
    Rails.application.eager_load! if defined?(Rails) && Rails.respond_to?(:application) && Rails.application

    output = ENV.fetch("OUTPUT", "sig/accord.rbs")
    all = Accord::Schema.descendants
    schemas = all.select(&:name)
    require "fileutils"
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, Accord.rbs_document(schemas))

    message = "accord: wrote #{schemas.size} schema signature(s) to #{output}"
    skipped = all.size - schemas.size
    # Don't drop silently — anonymous schemas can't be named in RBS.
    message += " (skipped #{skipped} anonymous schema(s) — name them to include)" if skipped.positive?
    puts message
  end
end
