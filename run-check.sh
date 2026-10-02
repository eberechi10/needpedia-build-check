#!/usr/bin/env bash
#
# Four phases of the Needpedia daily build check:
#   build -> database -> start -> page
#
# Exits 0 only if all four pass. On failure it writes the failing step
# name and that step's last ~30 log lines under results/ and exits 1,
# so the workflow can record the result either way.
#
# Environment (all optional, with defaults):
#   RESULTS_DIR   where failed-step.txt and current-step.log go
#   COMPOSE_FILE  compose harness for this check
#   WEB_PORT      host port the web container publishes

set -uo pipefail

RESULTS_DIR="${RESULTS_DIR:-results}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.check.yml}"
WEB_PORT="${WEB_PORT:-3000}"

mkdir -p "$RESULTS_DIR"
echo "unknown" > "$RESULTS_DIR/failed-step.txt"
rm -f "$RESULTS_DIR/step-log.txt"
STEP_LOG="$RESULTS_DIR/current-step.log"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

cleanup() {
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  local step="$1"
  echo "$step" > "$RESULTS_DIR/failed-step.txt"
  {
    echo "----- first 10 lines of the failing step -----"
    head -n 10 "$STEP_LOG" 2>/dev/null || true
    echo "----- last 30 lines of the failing step -----"
    tail -n 30 "$STEP_LOG" 2>/dev/null || true
  } > "$RESULTS_DIR/step-log.txt"
  echo "::error::FAILED STEP: $step"
  exit 1
}

# Run one plain command as a check step, keeping its full output in the log.
run_step() {
  local step="$1"
  shift
  echo "----- STEP: $step -----"
  if "$@" 2>&1 | tee "$STEP_LOG"; then
    echo "----- STEP $step: ok -----"
    return 0
  fi
  echo "----- STEP $step: FAILED -----"
  fail "$step"
}

# ---------------------------------------------------------------
# 1) BUILD — Needpedia's own, unmodified Dockerfile.
#    Expected to fail at apt-get until PR #195 is merged.
# ---------------------------------------------------------------
run_step build compose build web

# ---------------------------------------------------------------
# 2) DATABASE — PostgreSQL 13 + Redis 7, wait, then create+migrate.
# ---------------------------------------------------------------
run_step database compose up -d db redis

echo "Waiting for PostgreSQL to accept connections..."
for i in $(seq 1 30); do
  if compose exec -T db pg_isready -U needpedia -d needpedia_development >/dev/null 2>&1; then
    echo "PostgreSQL is ready."
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    {
      echo "PostgreSQL did not become ready in time."
      echo "Recent db logs:"
      compose logs --tail 30 db 2>&1 || true
    } | tee "$STEP_LOG"
    fail database
  fi
done

echo "Waiting for Redis..."
for i in $(seq 1 30); do
  pong="$(compose exec -T redis redis-cli ping 2>/dev/null || true)"
  if [ "$pong" = "PONG" ]; then
    echo "Redis is ready."
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    {
      echo "Redis did not become ready in time."
      echo "Recent redis logs:"
      compose logs --tail 30 redis 2>&1 || true
    } | tee "$STEP_LOG"
    fail database
  fi
done

run_step database compose run --rm -T web bundle exec rails db:migrate

# ---------------------------------------------------------------
# 3) START — bring the web container up and confirm it stays up.
# ---------------------------------------------------------------
run_step start compose up -d web

echo "Waiting for the web container to report state=running..."
state=""
for i in $(seq 1 30); do
  state="$(compose ps --format '{{.State}}' web 2>/dev/null | tail -n 1 || true)"
  if [ "$state" = "running" ]; then
    echo "Web container is running."
    break
  fi
  if [ "$state" = "exited" ] || [ "$state" = "dead" ]; then
    echo "Web container stopped (state: $state). Recent logs:" | tee "$STEP_LOG"
    compose logs --tail 30 web >> "$STEP_LOG" 2>&1 || true
    fail start
  fi
  sleep 2
done
if [ "$state" != "running" ]; then
  echo "Web container is not running (state: ${state:-none}). Recent logs:" | tee "$STEP_LOG"
  compose logs --tail 30 web >> "$STEP_LOG" 2>&1 || true
  fail start
fi

# ---------------------------------------------------------------
# 4) PAGE — the home page must answer HTTP 200.
# ---------------------------------------------------------------
echo "Waiting for http://localhost:${WEB_PORT}/ to answer 200..."
code=""
for i in $(seq 1 90); do
  code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "http://localhost:${WEB_PORT}/" || true)"
  if [ "$code" = "200" ]; then
    echo "Home page answered 200."
    break
  fi
  sleep 2
done
if [ "$code" != "200" ]; then
  echo "Home page answered ${code:-nothing} after waiting. Recent web logs:" | tee "$STEP_LOG"
  compose logs --tail 30 web >> "$STEP_LOG" 2>&1 || true
  fail page
fi

# All four phases passed.
: > "$RESULTS_DIR/failed-step.txt"
rm -f "$RESULTS_DIR/step-log.txt"
echo "BUILD CHECK PASSED"
exit 0
