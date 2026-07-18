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

    it "scopes the source with from:" do
      input = schema
      controller_class = build_controller do
        accord :employee, input, from: -> { params[:employee] }
      end
      controller = controller_class.new({ employee: { name: "Ada" } })

      expect(controller.employee.name).to eq("Ada")
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
