# frozen_string_literal: true

describe "sensitive fields" do
  recorder = Struct.new(:events) do
    def instrument(event, **payload)
      events << { event:, payload: }
    end
  end

  let(:events) { [] }

  let(:schema) do
    Class.new(Accord::Schema) do
      ssn    :taxpayer_id
      ein    :employer_id, sensitive: false
      string :api_key, sensitive: true, length: 1..8
      string :name
    end
  end

  around do |example|
    previous = Accord.notifier
    Accord.notifier = recorder.new(events)
    example.run
    Accord.notifier = previous
  end

  def error_for(input, field)
    schema.parse(input).errors.find { |e| e.field == field }
  end

  describe "which fields are sensitive" do
    it "defaults to the type's own answer, and honors a per-field override" do
      fields = schema.fields
      expect(fields[:taxpayer_id].sensitive?).to be true    # ssn type says so
      expect(fields[:employer_id].sensitive?).to be false   # ein type does, field opts out
      expect(fields[:api_key].sensitive?).to be true        # plain string opts in
      expect(fields[:name].sensitive?).to be false
    end
  end

  describe "coercion errors" do
    it "withholds the rejected value from the error and the notification" do
      error = error_for({ taxpayer_id: "666-45-6789" }, :taxpayer_id)

      expect(error.code).to eq(:invalid_ssn)
      expect(error.input).to eq(Accord::REDACTED)
      expect(error.to_h).not_to include(input: "666-45-6789")

      payload = events.first[:payload]
      expect(payload[:input]).to eq(Accord::REDACTED)
    end

    it "still reports the value for a field that opted out" do
      expect(error_for({ employer_id: "nope" }, :employer_id).input).to eq("nope")
    end

    it "leaves non-sensitive fields alone" do
      expect(error_for({ name: [] }, :name).input).to eq([])
    end
  end

  describe "validation errors" do
    it "withholds a valid-but-rejected value" do
      error = error_for({ api_key: "way-too-long-to-pass" }, :api_key)

      expect(error.code).to eq(:invalid_length)
      expect(error.value).to eq(Accord::REDACTED)
      expect(error.metadata).to include(min: 1, max: 8)   # rule metadata is not the secret
    end
  end

  describe "strict mode" do
    it "raises without the rejected value attached" do
      expect { schema.parse({ taxpayer_id: "666-45-6789" }, strict: true) }
        .to raise_error(Accord::CoercionError) { |e| expect(e.input).to eq(Accord::REDACTED) }
    end
  end

  describe "#inspect" do
    it "redacts sensitive values but keeps the rest readable" do
      input = schema.parse({ taxpayer_id: "123-45-6789", name: "Ada", api_key: "s3cret" })

      expect(input.inspect).to include("name=\"Ada\"", "taxpayer_id=#{Accord::REDACTED}",
                                       "api_key=#{Accord::REDACTED}")
      expect(input.inspect).not_to include("123-45-6789", "s3cret")
    end

    it "does not change what the readers return" do
      input = schema.parse({ taxpayer_id: "123-45-6789" })

      expect(input.taxpayer_id).to eq("123-45-6789")
      expect(input.to_h[:taxpayer_id]).to eq("123-45-6789")
    end
  end

  describe "standalone type parsing" do
    it "keeps the rejected value out of the log line" do
      logger = Struct.new(:lines) do
        def warn(line) = lines << line
      end.new([])

      previous = Accord.logger
      Accord.logger = logger
      Accord::Types::SSN.new.parse("666-45-6789")
      Accord::Types::Email.new.parse("nope")

      expect(logger.lines.first).to include(Accord::REDACTED)
      expect(logger.lines.first).not_to include("6789")
      expect(logger.lines.last).to include("nope")   # email isn't sensitive
    ensure
      Accord.logger = previous
    end
  end
end
