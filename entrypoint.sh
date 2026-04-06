#!/bin/sh
set -e

SCHEMA_REPO="${SCHEMA_REPO:-orion-dbs-community/website}"
SCHEMA_PATH="${SCHEMA_PATH:-data}"
DATA_DIR="${SCHEMA_DIR:-/data}"

echo "Fetching schemas from github.com/${SCHEMA_REPO}/${SCHEMA_PATH} ..."

FILES=$(curl -sf \
  "https://api.github.com/repos/${SCHEMA_REPO}/contents/${SCHEMA_PATH}" \
  | jq -r '.[] | select(.name | endswith(".jsonl")) | .download_url')

if [ -z "$FILES" ]; then
  echo "Warning: could not fetch schema list — falling back to cached data in ${DATA_DIR}"
else
  mkdir -p "$DATA_DIR"
  echo "$FILES" | while read -r url; do
    name=$(basename "$url")
    echo "  -> $name"
    curl -sf "$url" -o "${DATA_DIR}/${name}"
  done
  echo "Schema refresh complete."
fi

exec Rscript /server.R
