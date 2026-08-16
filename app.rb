# frozen_string_literal: true

require "sinatra/base"
require "securerandom"

# The application. Routes stay thin: parse params, call a service object, render.
# Business rules and SQL live in app/services and app/models — never here.
class App < Sinatra::Base
  configure do
    set :root, __dir__
    set :erb, escape_html: true
    set :sessions, secret: ENV.fetch("SECRET_KEY_BASE") { SecureRandom.hex(64) }
    enable :logging
    set :show_exceptions, false if ENV["RACK_ENV"] == "production"
  end

  # Current is the request-scoped data boundary (NOT authorization). Reset it
  # around every request so nothing leaks between them.
  before do
    Current.reset!
    Current.request_id = env["HTTP_X_REQUEST_ID"] || SecureRandom.uuid
  end
  after { Current.reset! }

  # Liveness/readiness: 200 once the process can reach the DB.
  get "/up" do
    DB.test_connection
    content_type :json
    '{"status":"ok"}'
  end

  get "/" do
    @notes = Note.recent.limit(50).all
    erb :"notes/index"
  end

  post "/notes" do
    result = Notes::Create.call(params)
    if result.success?
      redirect "/"
    else
      @errors = result.failure
      @notes  = Note.recent.limit(50).all
      status 422
      erb :"notes/index"
    end
  end
end
