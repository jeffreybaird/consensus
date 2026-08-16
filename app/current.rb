# frozen_string_literal: true

# Request-scoped context, thread-local so concurrent Puma threads don't share it.
# This is the DATA boundary (who/which tenant) — authorization lives in policies.
module Current
  class << self
    def user       = store[:user]
    def account    = store[:account]
    def request_id = store[:request_id]

    # Ruby forbids endless setter methods, so these stay classic.
    def user=(value)    ; store[:user] = value        ; end
    def account=(value) ; store[:account] = value      ; end
    def request_id=(id) ; store[:request_id] = id      ; end

    def reset!
      Thread.current[:current_attributes] = {}
    end

    private

    def store
      Thread.current[:current_attributes] ||= {}
    end
  end
end
