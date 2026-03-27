#!/usr/bin/env bash

set -euo pipefail

TARGET_CONTAINER="${TARGET_CONTAINER:-local-ai-packaged-neo4j-1}"
TARGET_DATABASE="${TARGET_DATABASE:-neo4j}"
TARGET_USER="${TARGET_USER:-neo4j}"
TARGET_PASSWORD="${TARGET_PASSWORD:-${NEO4J_PASSWORD:-demodemo}}"

SOURCE_CONTAINER="${SOURCE_CONTAINER:-finance-kg-poc-neo4j}"
SOURCE_DATABASE="${SOURCE_DATABASE:-kg-test-db}"
SOURCE_USER="${SOURCE_USER:-neo4j}"
SOURCE_PASSWORD="${SOURCE_PASSWORD:-${SOURCE_NEO4J_PASSWORD:-${NEO4J_PASSWORD:-demodemo}}}"

ARTIFACT_ROOT="${ARTIFACT_ROOT:-/home/gilles/local-ai-packaged/Finance_dashboard/test-artifacts/neo4j-cutover}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RUN_DIR="${ARTIFACT_ROOT}/${RUN_ID}"
TARGET_DUMP_DIR="${RUN_DIR}/target-rollback"
SOURCE_DUMP_DIR="${RUN_DIR}/source-dump"
FINGERPRINT_DIR="${RUN_DIR}/fingerprints"
RESTART_SOURCE_AFTER_DUMP="${RESTART_SOURCE_AFTER_DUMP:-true}"

mkdir -p "${TARGET_DUMP_DIR}" "${SOURCE_DUMP_DIR}" "${FINGERPRINT_DIR}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

container_image() {
  docker inspect --format '{{.Config.Image}}' "$1"
}

capture_query() {
  local container="$1"
  local username="$2"
  local password="$3"
  local database="$4"
  local query="$5"
  local output_path="$6"

  docker exec "$container" cypher-shell -u "$username" -p "$password" -d "$database" "$query" >"$output_path"
}

capture_fingerprints() {
  local label="$1"
  local container="$2"
  local username="$3"
  local password="$4"
  local database="$5"
  local prefix="${FINGERPRINT_DIR}/${label}"

  capture_query "$container" "$username" "$password" system \
    "SHOW DATABASES YIELD name, currentStatus, default RETURN name, currentStatus, default ORDER BY name" \
    "${prefix}.show-databases.txt"
  capture_query "$container" "$username" "$password" "$database" \
    "SHOW CONSTRAINTS YIELD name, type, entityType, labelsOrTypes, properties RETURN name, type, entityType, labelsOrTypes, properties ORDER BY name" \
    "${prefix}.show-constraints.txt"
  capture_query "$container" "$username" "$password" "$database" \
    "MATCH (n) RETURN labels(n) AS labels, count(*) AS count ORDER BY count DESC, labels" \
    "${prefix}.node-label-counts.txt"
  capture_query "$container" "$username" "$password" "$database" \
    "MATCH ()-[r]->() RETURN type(r) AS type, count(*) AS count ORDER BY count DESC, type" \
    "${prefix}.relationship-counts.txt"
}

ensure_container_exists() {
  docker inspect "$1" >/dev/null 2>&1 || {
    printf 'Container not found: %s\n' "$1" >&2
    exit 1
  }
}

ensure_container_running() {
  local state
  state="$(docker inspect --format '{{.State.Running}}' "$1")"
  if [[ "$state" != "true" ]]; then
    printf 'Container must be running for fingerprint capture: %s\n' "$1" >&2
    exit 1
  fi
}

admin_dump() {
  local container="$1"
  local database="$2"
  local dump_dir="$3"
  local image
  image="$(container_image "$container")"

  docker run --rm \
    --volumes-from "$container" \
    -v "${dump_dir}:/backups" \
    --entrypoint neo4j-admin \
    "$image" \
    database dump "$database" --to-path=/backups --overwrite-destination=true
}

admin_load() {
  local container="$1"
  local database="$2"
  local dump_dir="$3"
  local image
  image="$(container_image "$container")"

  docker run --rm \
    --volumes-from "$container" \
    -v "${dump_dir}:/backups" \
    --entrypoint neo4j-admin \
    "$image" \
    database load "$database" --from-path=/backups --overwrite-destination=true
}

require_command docker
ensure_container_exists "$TARGET_CONTAINER"
ensure_container_exists "$SOURCE_CONTAINER"
ensure_container_running "$TARGET_CONTAINER"
ensure_container_running "$SOURCE_CONTAINER"

printf '==> Cutover run directory: %s\n' "$RUN_DIR"
printf '==> Capturing pre-cutover fingerprints\n'
capture_fingerprints target-pre "$TARGET_CONTAINER" "$TARGET_USER" "$TARGET_PASSWORD" "$TARGET_DATABASE"
capture_fingerprints source-pre "$SOURCE_CONTAINER" "$SOURCE_USER" "$SOURCE_PASSWORD" "$SOURCE_DATABASE"

printf '==> Stopping target container for rollback dump\n'
docker stop "$TARGET_CONTAINER" >/dev/null
printf '==> Creating rollback dump of %s:%s\n' "$TARGET_CONTAINER" "$TARGET_DATABASE"
admin_dump "$TARGET_CONTAINER" "$TARGET_DATABASE" "$TARGET_DUMP_DIR"

printf '==> Stopping source container for source dump\n'
docker stop "$SOURCE_CONTAINER" >/dev/null
printf '==> Creating source dump of %s:%s\n' "$SOURCE_CONTAINER" "$SOURCE_DATABASE"
admin_dump "$SOURCE_CONTAINER" "$SOURCE_DATABASE" "$SOURCE_DUMP_DIR"

if [[ "$RESTART_SOURCE_AFTER_DUMP" == "true" ]]; then
  printf '==> Restarting source container to keep rollback comparison available\n'
  docker start "$SOURCE_CONTAINER" >/dev/null
fi

printf '==> Loading source dump into target database %s\n' "$TARGET_DATABASE"
admin_load "$TARGET_CONTAINER" "$TARGET_DATABASE" "$SOURCE_DUMP_DIR"

printf '==> Restarting target container\n'
docker start "$TARGET_CONTAINER" >/dev/null

printf '\nCutover artifacts\n'
printf '  run dir: %s\n' "$RUN_DIR"
printf '  rollback dump dir: %s\n' "$TARGET_DUMP_DIR"
printf '  source dump dir: %s\n' "$SOURCE_DUMP_DIR"
printf '  fingerprints dir: %s\n' "$FINGERPRINT_DIR"

printf '\nPost-cutover verification commands\n'
printf '  docker exec %s cypher-shell -u %s -p <password> -d system "SHOW DATABASES YIELD name, currentStatus, default RETURN name, currentStatus, default ORDER BY name"\n' "$TARGET_CONTAINER" "$TARGET_USER"
printf '  docker exec %s cypher-shell -u %s -p <password> -d %s "SHOW CONSTRAINTS YIELD name, type, entityType, labelsOrTypes, properties RETURN name, type, entityType, labelsOrTypes, properties ORDER BY name"\n' "$TARGET_CONTAINER" "$TARGET_USER" "$TARGET_DATABASE"
printf '  docker exec %s cypher-shell -u %s -p <password> -d %s "MATCH (n) RETURN labels(n) AS labels, count(*) AS count ORDER BY count DESC, labels"\n' "$TARGET_CONTAINER" "$TARGET_USER" "$TARGET_DATABASE"
printf '  docker exec %s cypher-shell -u %s -p <password> -d %s "MATCH ()-[r]->() RETURN type(r) AS type, count(*) AS count ORDER BY count DESC, type"\n' "$TARGET_CONTAINER" "$TARGET_USER" "$TARGET_DATABASE"

printf '\nRollback command sequence (if needed)\n'
printf '  docker stop %s\n' "$TARGET_CONTAINER"
printf '  docker run --rm --volumes-from %s -v %s:/backups --entrypoint neo4j-admin %s database load %s --from-path=/backups --overwrite-destination=true\n' "$TARGET_CONTAINER" "$TARGET_DUMP_DIR" "$(container_image "$TARGET_CONTAINER")" "$TARGET_DATABASE"
printf '  docker start %s\n' "$TARGET_CONTAINER"
