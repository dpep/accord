# frozen_string_literal: true

require "tapioca"
require "tapioca/dsl"
require "tapioca/dsl/compilers/accord_controller"

# Drives the controller DSL compiler's #decorate directly and prints the RBI.
describe Tapioca::Dsl::Compilers::AccordController do
  def rbi_for(constant)
    file = RBI::File.new(strictness: "strong")
    pipeline = Tapioca::Dsl::Pipeline.new(requested_constants: [], requested_compilers: [described_class])
    described_class.new(pipeline, file.root, constant, {}).decorate
    Tapioca::DEFAULT_RBI_FORMATTER.print_file(file)
  end

  # A controller-like class (no Rails needed) that includes the helpers.
  def controller_with(&body)
    klass = Class.new do
      def self.rescue_from(*); end
      include Accord::ControllerHelpers
    end
    klass.class_eval(&body)
    klass
  end

  it "types a schema reader as its schema and a list reader as an array" do
    stub_const("CreateEmployee", Class.new(Accord::Schema) { string :name, required: true })
    controller = controller_with do
      accord :employee, CreateEmployee
      accord :people, [CreateEmployee]
    end
    stub_const("EmployeesController", controller)

    rbi = rbi_for(EmployeesController)

    expect(rbi).to include("sig { returns(CreateEmployee) }")
    expect(rbi).to include("def employee; end")
    expect(rbi).to include("sig { returns(T::Array[CreateEmployee]) }")
    expect(rbi).to include("def people; end")
  end

  it "types an inline block reader by its minted constant" do
    controller = controller_with do
      accord :search do
        string :term, :required
      end
    end
    stub_const("SearchController", controller)

    expect(rbi_for(SearchController)).to include("sig { returns(SearchController::SearchInput) }")
  end
end
