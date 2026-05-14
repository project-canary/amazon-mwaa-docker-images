#!/bin/bash
# Bootstrap local MWAA on startup:
#   1. Import Airflow connections from /run/secrets/connections.json (written by
#      start-local.sh on the host using local AWS credentials, mounted read-only
#      from a temp directory outside the repo).
#   2. Import Airflow pools from /usr/local/airflow/startup/pools.json (checked
#      into the repo alongside this script).

# --- Connections ---
CONNECTIONS_FILE="/run/secrets/connections.json"

if [ ! -f "$CONNECTIONS_FILE" ]; then
    echo "No connections.json found at ${CONNECTIONS_FILE} — skipping connection import"
else
    echo "Importing connections from ${CONNECTIONS_FILE}..."
    airflow connections import --overwrite "$CONNECTIONS_FILE"
    echo "Connections imported successfully"
fi

# --- Pools ---
POOLS_FILE="/usr/local/airflow/startup/pools.json"

if [ ! -f "$POOLS_FILE" ]; then
    echo "No pools.json found at ${POOLS_FILE} — skipping pool import"
else
    echo "Importing pools from ${POOLS_FILE}..."
    airflow pools import "$POOLS_FILE"
    echo "Pools imported successfully"
fi
