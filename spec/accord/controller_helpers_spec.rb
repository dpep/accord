# frozen_string_literal: true

require "accord/controller_helpers"

RSpec.describe Accord::ControllerHelpers do
  let(:schema) do
    Class.new(Accord::Schema) do
      string :name, required: true
    end
  end

  # A minimal stand-in for an ActionController that captures rescue_from
  # registrations and render calls — no Rails required. The block customizes
  # the controller (declaring inputs, overriding rendering).
  def build_controller(&body)
    klass = Class.new do
      class << self
        def rescue_handlers
          @rescue_handlers ||= {}
        end

        def rescue_from(klass, &block)
          rescue_handlers[klass] = block
        end
      end

      include Accord::ControllerHelpers

      attr_reader :rendered

      def initialize(params = {})
        @params = params
      end

      def params
        @params
      end

      def render(**args)
        @rendered = args
      end

      # Mimic Rails dispatch: run the action, routing raised exceptions through
      # the registered rescue_from handlers.
      def dispatch(&action)
        instance_exec(&action)
      rescue StandardError => e
        handler = self.class.rescue_handlers.find { |klass, _| e.is_a?(klass) }&.last
        raise unless handler

        instance_exec(e, &handler)
      end
    end

    klass.class_eval(&body) if body
    klass
  end

  it "installs a rescue_from for InvalidInput on include" do
    expect(build_controller.rescue_handlers).to have_key(Accord::InvalidInput)
  end

  describe "the accord macro" do
    it "exposes a typed, memoized reader" do
      input = schema
      controller = build_controller { accord :employee, input }.new({ name: "Ada" })

      expect(controller.employee.name).to eq("Ada")
      expect(controller.employee).to be(controller.employee)
    end

    it "scopes the source with a proc from:" do
      input = schema
      controller_class = build_controller do
        accord :employee, input, from: -> { params[:employee] }
      end
      controller = controller_class.new({ employee: { name: "Ada" } })

      expect(controller.employee.name).to eq("Ada")
    end

    it "scopes the source with a symbol from: (a params key)" do
      input = schema
      controller_class = build_controller do
        accord :employee, input, from: :employee
      end
      controller = controller_class.new({ employee: { name: "Ada" } })

      expect(controller.employee.name).to eq("Ada")
    end

    it "defines an anonymous schema inline from a block" do
      controller = build_controller do
        accord :employee do
          string :name, :required
        end
      end.new({ name: "Ada" })

      expect(controller.employee.name).to eq("Ada")
    end

    it "names the inline schema as a controller constant so it projects" do
      controller = build_controller
      stub_const("SearchController", controller)
      controller.class_eval do
        accord :query do
          string :term, :required
        end
      end

      expect(SearchController::QueryInput.name).to eq("SearchController::QueryInput")
      expect(SearchController::QueryInput.openapi[:properties]).to have_key(:term)
      expect(SearchController::QueryInput.rbi).to include("< Accord::Schema")
    end

    it "refuses to overwrite an existing non-schema constant" do
      expect do
        build_controller do
          const_set(:ReportInput, Class.new)   # a pre-existing, non-accord constant
          accord :report do
            string :name
          end
        end
      end.to raise_error(ArgumentError, /overwrite/)
    end

    it "names the inline schema explicitly with const:" do
      controller = build_controller
      stub_const("ReportsController", controller)
      controller.class_eval do
        accord :report, const: :ReportParams do
          string :name, :required
        end
      end

      expect(ReportsController::ReportParams.name).to eq("ReportsController::ReportParams")
      expect(controller.const_defined?(:ReportInput, false)).to be(false)  # default name unused
    end

    it "rejects const: without a block" do
      input = schema
      expect do
        build_controller { accord :employee, input, const: :Foo }
      end.to raise_error(ArgumentError, /inline/)
    end

    it "parses a list input with the [Schema] shorthand" do
      input = schema
      controller = build_controller { accord :people, [input], from: :people }
                   .new({ people: [{ name: "Ada" }, { name: "Bo" }] })

      expect(controller.people.map(&:name)).to eq(%w[Ada Bo])
    end

    it "aggregates list errors with index paths, rendered as a 422" do
      input = schema   # requires :name
      controller = build_controller { accord :people, [input], from: :people }
                   .new({ people: [{ name: "Ada" }, {}] })
      controller.dispatch { people }

      expect(controller.rendered[:status]).to eq(:unprocessable_entity)
      expect(controller.rendered[:json][:errors].first[:path]).to eq([1, :name])
    end

    it "rejects a list source with more than one schema" do
      input = schema
      expect { build_controller { accord :people, [input, input] } }.to raise_error(ArgumentError)
    end

    it "mints a projectable Schema::List constant for a list input" do
      controller = build_controller
      stub_const("ImportsController", controller)
      element = stub_const("Person", Class.new(Accord::Schema) { string :name, :required })
      controller.class_eval { accord :people, [element] }

      expect(ImportsController::PeopleInput).to be_a(Accord::Schema::List)
      expect(ImportsController::PeopleInput.openapi[:type]).to eq("array")
    end

    it "records declarations in an introspectable registry" do
      input = schema
      controller = build_controller do
        accord :employee, input
        accord :people, [input]
      end

      expect(controller.accord_inputs[:employee]).to eq(input)
      expect(controller.accord_inputs[:people]).to be_a(Accord::Schema::List)
    end

    it "inherits declarations into a subclass" do
      input = schema
      parent = build_controller { accord :employee, input }
      child = Class.new(parent)

      expect(child.accord_inputs).to have_key(:employee)
    end

    it "requires either a schema or a block" do
      expect { build_controller { accord :employee } }.to raise_error(ArgumentError)
    end

    it "rejects both a schema and a block" do
      input = schema
      expect do
        build_controller { accord(:employee, input) { string :name } }
      end.to raise_error(ArgumentError)
    end

    it "raises InvalidInput, rendered as a 422, for invalid params" do
      input = schema
      controller = build_controller { accord :employee, input }.new({})
      controller.dispatch { employee }

      expect(controller.rendered[:status]).to eq(:unprocessable_entity)
      expect(controller.rendered[:json][:errors].first[:code]).to eq(:required)
    end
  end

  describe "render_accord_errors" do
    it "is overridable to customize the response" do
      input = schema
      controller_class = build_controller do
        accord :employee, input

        private

        def render_accord_errors(error)
          render json: { count: error.errors.size }, status: :bad_request
        end
      end
      controller = controller_class.new({})
      controller.dispatch { employee }

      expect(controller.rendered[:status]).to eq(:bad_request)
      expect(controller.rendered[:json][:count]).to eq(1)
    end
  end
end
