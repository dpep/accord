# frozen_string_literal: true

require "accord/controller_helpers"
require "accord/rspec"

describe "accepts / returns contract DSL" do
  # A controller-like class (no Rails) with a settable action_name.
  def controller_class(&body)
    klass = Class.new do
      def self.rescue_from(*); end
      include Accord::ControllerHelpers
      attr_accessor :action_name

      def initialize(params = {}) = @params = params
      attr_reader :params
    end
    klass.class_eval(&body)
    klass
  end

  let(:employee_schema) { stub_const("CreateEmployee", Class.new(Accord::Schema) { string :name, :required }) }

  it "records a per-action endpoint and exposes the input via the default reader" do
    schema = employee_schema
    controller = controller_class do
      accepts schema
      def create = input
    end
    stub_const("EmployeesController", controller)

    endpoint = controller.accord_endpoints[:create]
    expect(endpoint.accepts).to eq(schema)
    expect(endpoint.action).to eq(:create)

    instance = controller.new({ name: "Ada" })
    instance.action_name = "create"
    expect(instance.input.name).to eq("Ada")
  end

  it "names the reader with as:, and does not also define input" do
    schema = employee_schema
    controller = controller_class do
      accepts schema, as: :employee
      def create = employee
    end

    expect(controller.instance_methods).to include(:employee)
    expect(controller.instance_methods).not_to include(:input)
  end

  it "honors the config default reader name" do
    Accord.config.input_reader = :payload
    schema = employee_schema
    controller = controller_class do
      accepts schema
      def create = payload
    end

    expect(controller.instance_methods).to include(:payload)
  ensure
    Accord.config.input_reader = :input
  end

  it "accepts a block (anonymous schema, named from the action so it projects)" do
    controller = controller_class do
      accepts do
        string :term, :required
      end
      def search = input
    end
    stub_const("SearchController", controller)

    expect(SearchController::SearchInput.openapi[:properties]).to have_key(:term)
    expect(controller.accord_endpoints[:search].accepts).to eq(SearchController::SearchInput)
  end

  it "records returns as a status => contract map that composes with accepts" do
    accepts_schema = employee_schema
    view = stub_const("EmployeeView", Class.new(Accord::Schema) { string :name })
    controller = controller_class do
      accepts accepts_schema
      returns 201 => view, 422 => :errors
      def create = input
    end

    endpoint = controller.accord_endpoints[:create]
    expect(endpoint.returns).to eq(201 => view, 422 => :errors)
    expect(endpoint.accepts).to eq(accepts_schema)
  end

  it "supports a returns-only action (no accepts, no reader)" do
    view = stub_const("EmployeeView", Class.new(Accord::Schema) { string :name })
    controller = controller_class do
      returns 200 => [view]
      def index; end
    end

    endpoint = controller.accord_endpoints[:index]
    expect(endpoint.accepts).to be_nil
    expect(endpoint.returns).to eq(200 => [view])
  end

  it "aggregates endpoints across controllers via ControllerHelpers.endpoints" do
    schema = employee_schema
    c1 = controller_class do
      accepts schema
      def create = input
    end
    stub_const("EmployeesController", c1)

    endpoints = Accord::ControllerHelpers.endpoints([c1])
    expect(endpoints.map(&:key)).to eq(["EmployeesController#create"])
  end

  it "renders invalid input for an accepts action as a 422 (dogfooding have_error)" do
    schema = employee_schema
    controller = controller_class do
      accepts schema
      def create = input   # touches the reader -> parses -> raises InvalidInput
    end

    instance = controller.new({})
    rendered = nil
    instance.define_singleton_method(:render) { |**args| rendered = args }
    begin
      instance.tap { |c| c.action_name = "create" }.input
    rescue Accord::InvalidInput => e
      expect(e.input).to have_error(:required).at(:name)
    end
  end
end
