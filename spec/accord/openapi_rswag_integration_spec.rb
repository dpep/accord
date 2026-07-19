# frozen_string_literal: true

# Integration coverage for the rswag wiring documented in docs/openapi.md:
# Accord fills `components.schemas` (via Accord.openapi_schemas), rswag describes
# the paths, and they connect through `$ref`. We assemble that document here and
# validate it end to end — the real risk is that the refs rswag emits resolve to
# the components Accord generates. (A literal rswag run additionally needs a
# Rack app + request specs; this exercises the contract they share.)
RSpec.describe "OpenAPI / rswag integration" do
  before do
    stub_const("Address", Class.new(Accord::Schema) do
      string :city, :required
      string :zip do
        format(/\A\d{5}\z/)
      end
    end)
    stub_const("CreateEmployee", Class.new(Accord::Schema) do
      string :name, :required
      currency :salary, :positive
      boolean :active, default: true
      object :address, Address
    end)
  end

  # The `openapi_specs` document from docs/openapi.md: Accord components plus a
  # path whose request body $refs a schema.
  let(:document) do
    {
      openapi: "3.0.1",
      info: { title: "API", version: "v1" },
      paths: {
        "/employees" => {
          "post" => {
            requestBody: {
              content: {
                "application/json" => { schema: { "$ref" => "#/components/schemas/CreateEmployee" } },
              },
            },
            responses: { "201" => { description: "created" } },
          },
        },
      },
      components: { schemas: Accord.openapi_schemas(CreateEmployee) },
    }
  end

  it "registers each schema plus its nested schemas as components" do
    expect(document[:components][:schemas].keys).to contain_exactly("CreateEmployee", "Address")
  end

  it "projects field types, requireds, validator constraints, and nested $refs" do
    employee = document[:components][:schemas]["CreateEmployee"]
    address = document[:components][:schemas]["Address"]

    expect(employee[:type]).to eq("object")
    expect(employee[:required]).to include(:name)
    expect(employee[:properties][:salary]).to include(type: "string", format: "decimal")
    expect(employee[:properties][:address]).to eq("$ref" => "#/components/schemas/Address")
    expect(address[:properties][:zip]).to include(pattern: "\\A\\d{5}\\z")
  end

  it "resolves every $ref in the document to a defined component" do
    keys = document[:components][:schemas].keys
    refs = collect_refs(document)

    expect(refs).to include("#/components/schemas/CreateEmployee", "#/components/schemas/Address")
    refs.each { |ref| expect(keys).to include(ref.split("/").last) }
  end

  # Recursively gather every "$ref" value in the document (paths and components).
  def collect_refs(node)
    case node
    when Hash then node.flat_map { |key, value| key.to_s == "$ref" ? [value] : collect_refs(value) }
    when Array then node.flat_map { |element| collect_refs(element) }
    else []
    end
  end
end
