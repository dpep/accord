# frozen_string_literal: true

require "bigdecimal"

RSpec.describe "validation framework" do
  def schema(&block)
    Class.new(Accord::Schema, &block)
  end

  describe "built-in validators" do
    it "required reports a missing field" do
      s = schema { string(:name) { required } }
      expect(s.parse({}).errors.map(&:code)).to eq([:required])
    end

    it "positive" do
      s = schema { currency(:salary) { positive } }
      expect(s.parse({ salary: "-5" }).errors.first.code).to eq(:not_positive)
      expect(s.parse({ salary: "5" })).to be_valid
    end

    it "negative" do
      s = schema { integer(:delta) { negative } }
      expect(s.parse({ delta: "5" }).errors.first.code).to eq(:not_negative)
    end

    it "non_zero" do
      s = schema { integer(:qty) { non_zero } }
      expect(s.parse({ qty: "0" }).errors.first.code).to eq(:zero)
    end

    it "min" do
      s = schema { integer(:age) { min 18 } }
      error = s.parse({ age: "5" }).errors.first
      expect(error.code).to eq(:too_small)
      expect(error.metadata).to eq(expected: 18)
    end

    it "max" do
      s = schema { integer(:age) { max 120 } }
      expect(s.parse({ age: "200" }).errors.first.code).to eq(:too_large)
    end

    it "between" do
      s = schema { integer(:age) { between 18..120 } }
      error = s.parse({ age: "5" }).errors.first
      expect(error.code).to eq(:out_of_range)
      expect(error.metadata).to eq(min: 18, max: 120)
    end

    it "length" do
      s = schema { string(:name) { length 1..3 } }
      expect(s.parse({ name: "abcd" }).errors.first.code).to eq(:invalid_length)
      expect(s.parse({ name: "ab" })).to be_valid
    end

    it "inclusion" do
      s = schema { string(:status) { inclusion %w[pending approved] } }
      error = s.parse({ status: "nope" }).errors.first
      expect(error.code).to eq(:not_included)
      expect(error.metadata).to eq(allowed: %w[pending approved])
    end

    it "exclusion" do
      s = schema { string(:name) { exclusion %w[admin root] } }
      expect(s.parse({ name: "root" }).errors.first.code).to eq(:excluded)
    end

    it "format" do
      s = schema { string(:slug) { format(/\A[a-z0-9-]+\z/) } }
      expect(s.parse({ slug: "Bad Slug" }).errors.first.code).to eq(:invalid_format)
      expect(s.parse({ slug: "ok-slug" })).to be_valid
    end
  end

  describe "structured errors" do
    it "carry path, code, validator, value, and metadata" do
      s = schema { integer(:discount) { min 0 } }
      error = s.parse({ discount: "-5" }).errors.first

      expect(error.to_h).to eq(
        path: [:discount], field: :discount, code: :too_small,
        validator: :min, value: -5, expected: 0,
      )
    end
  end

  describe "composition" do
    it "runs every validator and collects every violation" do
      s = schema do
        integer(:age) do
          min 18
          non_zero
        end
      end

      # 0 is both below the minimum and zero
      expect(s.parse({ age: "0" }).errors.map(&:code)).to contain_exactly(:too_small, :zero)
    end
  end

  describe "nested validation" do
    it "produces nested paths with no special handling" do
      inner = schema { currency(:salary) { positive } }
      outer = Class.new(Accord::Schema)
      outer.object(:employee, inner)

      error = outer.parse({ employee: { salary: "-5" } }).errors.first
      expect(error.path).to eq([:employee, :salary])
      expect(error.code).to eq(:not_positive)
    end
  end

  describe "custom validators" do
    it "supports an inline validate block" do
      s = schema do
        currency(:salary) do
          validate(:increment) { |v| error(:bad_increment) unless (v % 100).zero? }
        end
      end

      error = s.parse({ salary: "150" }).errors.first
      expect(error.code).to eq(:bad_increment)
      expect(error.validator).to eq(:increment)
    end

    it "supports a reusable validator class" do
      stub_const("EvenValidator", Class.new(Accord::Validators::Base) do
        def validate(value, collector)
          collector.add(:odd) unless value.even?
        end
      end)
      s = schema { integer(:count) { validator EvenValidator } }

      error = s.parse({ count: "3" }).errors.first
      expect(error.code).to eq(:odd)
      expect(error.validator).to eq(:even_validator)
    end
  end

  describe "introspection" do
    it "exposes a field's validators" do
      s = schema do
        currency(:salary) do
          required
          positive
        end
      end
      field = s.fields[:salary]

      expect(field.required?).to be(true)
      expect(field.validators.map(&:class)).to include(
        Accord::Validators::Required, Accord::Validators::Positive
      )
    end
  end

  describe "OpenAPI contributions" do
    it "between contributes minimum/maximum" do
      s = schema { integer(:age) { between 18..120 } }
      expect(s.fields[:age].openapi).to include(minimum: 18, maximum: 120)
    end

    it "length contributes minLength/maxLength" do
      s = schema { string(:name) { length 1..50 } }
      expect(s.fields[:name].openapi).to include(minLength: 1, maxLength: 50)
    end

    it "inclusion contributes enum" do
      s = schema { iso_currency(:currency) { inclusion %w[USD EUR GBP] } }
      expect(s.fields[:currency].openapi).to include(enum: %w[USD EUR GBP])
    end
  end
end
