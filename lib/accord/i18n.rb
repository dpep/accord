# frozen_string_literal: true

# Optional i18n integration: registers Accord's default locale and the
# Accord::Messages rendering helpers. Loaded automatically by "accord/rails";
# in a non-Rails app, `require "accord/i18n"`.

require "i18n"
require_relative "messages"

locale = File.expand_path("locale/en.yml", __dir__)
I18n.load_path << locale unless I18n.load_path.include?(locale)
