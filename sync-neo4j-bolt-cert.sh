#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/home/gilles/local-ai-packaged/neo4j-certs"
CERT_SRC="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/wildcard_.chezgilles.ovh/wildcard_.chezgilles.ovh.crt"
KEY_SRC="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/wildcard_.chezgilles.ovh/wildcard_.chezgilles.ovh.key"
TMP_DIR="$(mktemp -d)"
UPDATED=0

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

mkdir -p "$BASE_DIR"
docker cp "caddy:${CERT_SRC}" "$TMP_DIR/fullchain.pem"
docker cp "caddy:${KEY_SRC}" "$TMP_DIR/privkey.pem"

if ! cmp -s "$TMP_DIR/fullchain.pem" "$BASE_DIR/fullchain.pem" 2>/dev/null; then
  install -m 644 "$TMP_DIR/fullchain.pem" "$BASE_DIR/fullchain.pem"
  UPDATED=1
fi

if ! cmp -s "$TMP_DIR/privkey.pem" "$BASE_DIR/privkey.pem" 2>/dev/null; then
  install -m 644 "$TMP_DIR/privkey.pem" "$BASE_DIR/privkey.pem"
  UPDATED=1
fi

if [ "$UPDATED" -eq 1 ]; then
  docker compose -f /home/gilles/local-ai-packaged/docker-compose.yml up -d neo4j >/dev/null
  echo "Neo4j Bolt cert updated and neo4j recreated"
else
  echo "Neo4j Bolt cert already current"
fi

openssl x509 -in "$BASE_DIR/fullchain.pem" -noout -subject -issuer -dates
