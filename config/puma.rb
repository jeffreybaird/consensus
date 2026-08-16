# frozen_string_literal: true

# Binds 0.0.0.0:$PORT so Caddy (by container name) and the compose healthcheck
# (127.0.0.1) both reach it. Keep the thread count modest: SQLite serializes
# writes, so more threads mainly means more lock contention.
port        Integer(ENV.fetch("PORT", 4000))
environment ENV.fetch("RACK_ENV", "development")
threads     1, Integer(ENV.fetch("PUMA_MAX_THREADS", 5))
# No pidfile: the container is ephemeral and runs unprivileged.
