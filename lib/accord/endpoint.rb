# frozen_string_literal: true

module Accord
  # A declared controller operation — the per-action contract recorded by the
  # `accepts`/`returns` decorators. Pure, introspectable data (no controller
  # coupling): the request `accepts` schema (a Schema class, a Schema::List, or
  # nil for an output-only action), the `returns` map of `status => contract`
  # (a Schema/List, or a symbol naming a shared response like `:errors`), and how
  # the input is sourced (`from`) and parsed (`strict`). Verb/path are filled in
  # from the router at OpenAPI-generation time.
  #
  # Introspect via `Accord.endpoints` (all) or `Controller.accord_endpoints`.
  # `verb`/`path` are nil until an OpenAPI generator fills them from the router.
  Endpoint = Data.define(:controller, :action, :accepts, :returns, :from, :strict, :reader, :verb, :path) do
    def accepts? = !accepts.nil?
    def returns? = !returns.empty?
    def routed? = !verb.nil? && !path.nil?
    def key = "#{controller}##{action}"
  end
end
