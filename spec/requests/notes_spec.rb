# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Notes", type: :request do
  it "lists existing notes" do
    Note.create(body: "a seeded note")

    get "/"

    expect(last_response).to be_ok
    expect(last_response.body).to include("a seeded note")
  end

  it "creates a note and redirects" do
    post "/notes", "body" => "written via request"

    expect(last_response.status).to eq(302)
    expect(Note.where(body: "written via request").count).to eq(1)
  end

  it "re-renders with 422 on invalid input" do
    post "/notes", "body" => ""

    expect(last_response.status).to eq(422)
  end
end
