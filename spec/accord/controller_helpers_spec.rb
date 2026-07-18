# frozen_string_literal: true

require "accord/controller_helpers"

RSpec.describe Accord::ControllerHelpers do
  # A minimal stand-in for an ActionController that captures rescue_from
  # registrations and render calls — no Rails required.
  let(:controller_class) do
    Class.new do
      class << self
        def rescue_handlers
          @rescue_handlers ||= {}
        end

        def rescue_from(klass, &block)
          rescue_handlers[klass] = block
        end
      end

      include Accord::ControllerHelpers

      attr_reader :params, :rendered

      def initialize(params)
        @params = params
      end

      def render(**args)
        @rendered = args
      end

      # Mimic Rails dispatch: run the action, routing raised exceptions through
      # the registered rescue_from handlers.
      def dispatch(schema)
        parse_input(schema)
      rescue StandardError => e
        handler = self.class.rescue_handlers.find { |klass, _| e.is_a?(klass) }&.last
        raise unless handler

        instance_exec(e, &handler)
      end
    end
  end

  let(:schema) do
    Class.new(Accord::Schema) do
      string :name, required: true
    end
  end

  it "installs a rescue_from for InvalidInput on include" do
    expect(controller_class.rescue_handlers).to have_key(Accord::InvalidInput)
  end

  it "returns the typed input for valid params" do
    controller = controller_class.new({ name: "Ada" })
    expect(controller.parse_input(schema).name).to eq("Ada")
  end

  it "raises InvalidInput carrying the errors for invalid params" do
    controller = controller_class.new({})

    expect { controller.parse_input(schema) }.to raise_error(Accord::InvalidInput) do |error|
      expect(error.errors.map(&:code)).to eq([:required])
    end
  end

  it "renders a 422 with structured errors through the rescue handler" do
    controller = controller_class.new({})
    controller.dispatch(schema)

    expect(controller.rendered[:status]).to eq(:unprocessable_entity)
    expect(controller.rendered[:json][:errors].first[:code]).to eq(:required)
  end

  it "reads unfiltered params from ActionController::Parameters-like objects" do
    params = Object.new
    def params.to_unsafe_h = { name: "Ada" }

    controller = controller_class.new(params)
    expect(controller.parse_input(schema).name).to eq("Ada")
  end
end
