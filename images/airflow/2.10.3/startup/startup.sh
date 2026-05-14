#!/bin/bash
# Bootstrap local MWAA on startup:
#   1. Import Airflow connections from /run/secrets/connections.json (written by
#      start-local.sh on the host using local AWS credentials, mounted read-only
#      from a temp directory outside the repo).
#   2. Strip role_arn from all AWS connections — locally the developer's SSO
#      identity has sufficient direct access; role assumption is for the MWAA
#      execution role in production and is not available to SSO principals.
#   3. Import Airflow pools from /usr/local/airflow/startup/pools.json (checked
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

# --- Strip role_arn from AWS connections ---
# In production, MWAA tasks assume IAM roles via the MWAA execution role.
# Locally, the developer's SSO identity cannot assume those roles (trust policy
# only allows the MWAA execution role).  Strip role_arn so boto uses the
# developer's direct credentials from ~/.aws instead.
echo "Stripping role_arn from AWS connections for local dev..."
python3 - <<'EOF'
import json
from airflow.utils.session import create_session
from airflow.models import Connection

with create_session() as session:
    conns = session.query(Connection).filter(Connection.conn_type == "aws").all()
    for conn in conns:
        try:
            extra = json.loads(conn.extra) if conn.extra else {}
            if "role_arn" in extra:
                del extra["role_arn"]
                conn.extra = json.dumps(extra)
                print(f"  Patched: {conn.conn_id}")
        except (json.JSONDecodeError, TypeError):
            pass
    session.commit()
EOF
echo "Done"

# --- Pools ---
POOLS_FILE="/usr/local/airflow/startup/pools.json"

if [ ! -f "$POOLS_FILE" ]; then
    echo "No pools.json found at ${POOLS_FILE} — skipping pool import"
else
    echo "Importing pools from ${POOLS_FILE}..."
    airflow pools import "$POOLS_FILE"
    echo "Pools imported successfully"
fi
