# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notes::Create do
  it "creates a note from valid params" do
    result = described_class.call("body" => "hello world")

    expect(result.success?).to be(true)
    expect(result.value!.body).to eq("hello world")
    expect(Note.count).to eq(1)
  end

  it "fails with a tagged Result when the body is blank" do
    result = described_class.call("body" => "   ")

    expect(result.failure?).to be(true)
    expect(result.failure.first).to eq(:validation)
    expect(Note.count).to eq(0)
  end
end
