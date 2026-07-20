# frozen_string_literal: true

describe "registry freeze!" do
  it "locks the validators registry against further registration" do
    registry = Accord::Validators::Registry.new.reset.freeze!
    expect { registry.register(:x, Accord::Validators::Positive) }.to raise_error(FrozenError)
  end

  it "locks the types registry against further registration" do
    registry = Accord::Types::Registry.new.freeze!
    expect { registry.register(:x, Accord::Types::String) }.to raise_error(FrozenError)
  end

  it "Accord.freeze! locks config too" do
    # a throwaway config object, so the global one stays mutable for other specs
    config = Accord::Configuration.new.freeze
    expect { config.strict = true }.to raise_error(FrozenError)
  end
end
