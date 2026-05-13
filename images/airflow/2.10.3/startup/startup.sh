#!/bin/bash
# Import Airflow connections from a Secrets Manager secret.
#
# The secret should be a JSON object in Airflow's connections import format:
#   {
#     "<conn_id>": {
#       "conn_type": "postgres",
#       "host": "...",
#       "login": "...",
#       "password": "...",
#       "port": 5432,
#       "schema": "..."
#     },
#     ...
#   }
#
# Set CONNECTIONS_SECRET_ID in your .env to enable this.

if [ -z "${CONNECTIONS_SECRET_ID}" ]; then
  echo "CONNECTIONS_SECRET_ID not set — skipping connection import"
  exit 0
fi

echo "Importing connections from Secrets Manager: ${CONNECTIONS_SECRET_ID}"

aws secretsmanager get-secret-value \
  --secret-id "${CONNECTIONS_SECRET_ID}" \
  --region "${AWS_REGION:-us-east-2}" \
  --query SecretString \
  --output text > /tmp/connections.json

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to fetch connections secret '${CONNECTIONS_SECRET_ID}'" >&2
  rm -f /tmp/connections.json
  exit 1
fi

airflow connections import /tmp/connections.json
rm -f /tmp/connections.json

echo "Connections imported successfully"