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

    endpoint = controller.accord_endpoints.find { |e| e.action == :create }
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
    expect(controller.accord_endpoints.find { |e| e.action == :search }.accepts).to eq(SearchController::SearchInput)
  end

  it "records returns as a status => contract map that composes with accepts" do
    accepts_schema = employee_schema
    view = stub_const("EmployeeView", Class.new(Accord::Schema) { string :name })
    controller = controller_class do
      accepts accepts_schema
      returns 201 => view, 422 => :errors
      def create = input
    end

    endpoint = controller.accord_endpoints.find { |e| e.action == :create }
    expect(endpoint.returns).to eq(201 => view, 422 => :errors)
    expect(endpoint.accepts).to eq(accepts_schema)
  end

  it "supports a returns-only action (no accepts, no reader)" do
    view = stub_const("EmployeeView", Class.new(Accord::Schema) { string :name })
    controller = controller_class do
      returns 200 => [view]
      def index; end
    end

    endpoint = controller.accord_endpoints.find { |e| e.action == :index }
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

  it "generates a valid OpenAPI document from the contracts" do
    require "openapi3_parser"
    require "json"
    stub_const("CreateEmployee", Class.new(Accord::Schema) { string :name, :required })
    stub_const("EmployeeView", Class.new(Accord::Schema) { string :name })
    controller = controller_class do
      accepts CreateEmployee
      returns 201 => EmployeeView, 422 => :errors
      def create = input
    end
    stub_const("EmployeesController", controller)

    resolver = ->(_c, action) { action == :create ? ["POST", "/employees"] : nil }
    doc = Accord::ControllerHelpers.openapi_document(
      info: { title: "API", version: "1" },
      endpoints: Accord::ControllerHelpers.endpoints([controller]),
      resolver:,
    )
    parsed = Openapi3Parser.load(JSON.parse(JSON.generate(doc)))

    expect(parsed.errors.to_a).to be_empty
    post = parsed.paths["/employees"].post
    expect(post.request_body.content["application/json"].schema.properties.keys).to include("name")
    expect(post.responses["201"].content["application/json"].schema.properties.keys).to include("name")
    expect(post.responses["422"]).not_to be_nil                                   # $ref AccordErrors, resolved
    expect(parsed.components.schemas.keys).to include("CreateEmployee", "EmployeeView")
  end

  it "gives responses reason-phrase descriptions and handles lists + no-content" do
    require "openapi3_parser"
    require "json"
    stub_const("EmployeeView", Class.new(Accord::Schema) { string :name })
    controller = controller_class do
      returns 200 => [EmployeeView]
      def index; end

      returns 204 => nil
      def destroy; end
    end
    stub_const("EmployeesController", controller)

    routes = { index: ["GET", "/employees"], destroy: ["DELETE", "/employees/{id}"] }
    doc = Accord::ControllerHelpers.openapi_document(
      info: { title: "API", version: "1" },
      endpoints: Accord::ControllerHelpers.endpoints([controller]),
      resolver: ->(_c, action) { routes[action] },
    )
    parsed = Openapi3Parser.load(JSON.parse(JSON.generate(doc)))

    expect(parsed.errors.to_a).to be_empty
    list = parsed.paths["/employees"].get.responses["200"]
    expect(list.description).to eq("OK")
    expect(list.content["application/json"].schema.type).to eq("array")
    no_content = parsed.paths["/employees/{id}"].delete.responses["204"]
    expect(no_content.description).to eq("No Content")
    expect(no_content.content["application/json"]).to be_nil
  end

  describe "single-controller versioning" do
    before do
      stub_const("V1Create", Class.new(Accord::Schema) { string :name, :required })
      stub_const("V2Create", Class.new(Accord::Schema) do
        string :name, :required
        string :email
      end)
    end

    def versioned_controller
      v1 = V1Create
      v2 = V2Create
      controller_class do
        accepts v1, version: 1
        accepts v2, version: 2
        returns 200 => v2, version: 2
        def create = input
      end
    end

    it "records one endpoint per version" do
      expect(versioned_controller.accord_endpoints.map(&:version)).to contain_exactly(1, 2)
    end

    it "parses the schema for the request's resolved version" do
      controller = versioned_controller
      Accord.config.version_resolver = ->(_) { 2 }
      instance = controller.new({ name: "Ada", email: "a@x.co" })
      instance.action_name = "create"

      expect(instance.input).to be_a(V2Create)
      expect(instance.input.email).to eq("a@x.co")
    ensure
      Accord.config.version_resolver = nil
    end

    it "resolves a different version to a different schema" do
      controller = versioned_controller
      Accord.config.version_resolver = ->(_) { 1 }
      instance = controller.new({ name: "Ada" }).tap { |c| c.action_name = "create" }

      expect(instance.input).to be_a(V1Create)
    ensure
      Accord.config.version_resolver = nil
    end

    it "generates a separate OpenAPI document per version" do
      controller = versioned_controller
      stub_const("EmployeesController", controller)
      endpoints = Accord::ControllerHelpers.endpoints([controller])
      resolver = ->(_c, action) { action == :create ? ["POST", "/employees"] : nil }

      v2 = Accord::ControllerHelpers.openapi_document(info: { title: "API", version: "2" }, version: 2, endpoints:, resolver:)

      expect(v2[:components][:schemas].keys).to include("V2Create")
      expect(v2[:components][:schemas].keys).not_to include("V1Create")
    end

    it "shares an unversioned returns across every version" do
      v1 = V1Create
      v2 = V2Create
      controller = controller_class do
        returns 422 => :errors                # shared across versions
        accepts v1, version: 1
        returns 200 => v1, version: 1
        accepts v2, version: 2
        returns 200 => v2, version: 2
        def create = input
      end

      controller.accord_endpoints.each do |endpoint|
        expect(endpoint.returns[422]).to eq(:errors)
      end
    end

    it "rejects an unversioned accepts mixed with versioned ones" do
      v1 = V1Create
      expect do
        controller_class do
          accepts v1                          # unversioned
          accepts V2Create, version: 2
          def create = input
        end
      end.to raise_error(ArgumentError, /can't mix/)
    end

    it "cross-checks a V-suffixed schema name against the declared version" do
      stub_const("CreateEmployeeV2", Class.new(Accord::Schema) { string :name })
      expect do
        controller_class do
          accepts CreateEmployeeV2, version: 1
          def create = input
        end
      end.to raise_error(ArgumentError, /version/)
    end

    it "accepts a non-integer version label (e.g. a date)" do
      controller = controller_class do
        accepts V1Create, version: "2024-01"
        def create = input
      end
      Accord.config.version_resolver = ->(_) { "2024-01" }
      instance = controller.new({ name: "Ada" }).tap { |c| c.action_name = "create" }

      expect(instance.input).to be_a(V1Create)
    ensure
      Accord.config.version_resolver = nil
    end

    it "auto-names an anonymous versioned block schema with the version suffix" do
      controller = controller_class do
        accepts version: 2 do
          string :name, :required
        end
        def create = input
      end
      stub_const("OrdersController", controller)

      expect(controller.accord_endpoints.first.accepts).to eq(OrdersController::CreateV2Input)
    end
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
