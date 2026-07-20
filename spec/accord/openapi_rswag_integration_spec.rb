# frozen_string_literal: true

require "openapi3_parser"
require "json"

# Integration coverage for the rswag wiring documented in docs/openapi.md:
# Accord fills `components.schemas` (via Accord.openapi_schemas), rswag describes
# the paths, and they connect through `$ref` (built with Schema.openapi_ref). We
# assemble that document and validate it with a real OpenAPI 3 parser — the risk
# is that the refs rswag emits resolve to the components Accord generates. (A
# literal rswag run additionally needs a Rack app + request specs; this
# exercises the contract they share.)
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

  # The `openapi_specs` document from docs/openapi.md: Accord components, and a
  # path whose request body $refs a schema via the Schema.openapi_ref helper.
  let(:document) do
    {
      openapi: "3.0.1",
      info: { title: "API", version: "v1" },
      paths: {
        "/employees" => {
          "post" => {
            requestBody: {
              required: true,
              content: { "application/json" => { schema: CreateEmployee.openapi_ref } },
            },
            responses: { "201" => { description: "created" } },
          },
        },
      },
      components: { schemas: Accord.openapi_schemas(CreateEmployee) },
    }
  end

  # Normalize to string keys the way a JSON serializer would, then parse/validate.
  let(:parsed) { Openapi3Parser.load(JSON.parse(JSON.generate(document))) }

  it "is a valid OpenAPI 3 document" do
    expect(parsed.errors.to_a).to be_empty
    expect(parsed).to be_valid
  end

  it "registers each schema plus its nested schemas as components" do
    expect(parsed.components.schemas.keys).to contain_exactly("CreateEmployee", "Address")
  end

  it "resolves the request-body $ref (from openapi_ref) to the schema" do
    schema = parsed.paths["/employees"].post.request_body.content["application/json"].schema

    expect(schema.properties.keys).to include("name", "salary", "address")
    expect(schema.required).to include("name")
  end

  it "resolves the nested $ref and carries validator constraints" do
    address = parsed.components.schemas["CreateEmployee"].properties["address"]

    expect(address.properties.keys).to include("city", "zip")
    expect(address.properties["zip"].pattern).to eq("\\A\\d{5}\\z")
  end
end
