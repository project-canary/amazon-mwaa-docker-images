#!/bin/bash
# Starts local MWAA development environment.
#
# Usage:
#   ./start-local.sh                        # one-time sync, then start stack
#   ./start-local.sh --watch                # sync + start stack + re-sync on file changes
#   ./start-local.sh /path/to/data-pipelines 2.10.3 --watch
#
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

# Parse args — pass everything through to sync_dags.py; extract --watch for background handling
SYNC_ARGS=()
WATCH=false
for arg in "$@"; do
    if [ "$arg" == "--watch" ]; then
        WATCH=true
    else
        SYNC_ARGS+=("$arg")
    fi
done

# Positional defaults (mirrors sync_dags.py defaults)
AIRFLOW_VERSION="${SYNC_ARGS[1]:-2.10.3}"
DATA_PIPELINES_DIR="${SYNC_ARGS[0]:-/c/Development/data-pipelines}"

ENV_FILE="images/airflow/$AIRFLOW_VERSION/.env"
PLUGINS_DIR="images/airflow/$AIRFLOW_VERSION/plugins"
PLUGINS_S3_DIR="s3://canary-etl-jobs/airflow/nonprod_2103/dependencies/"
MWAA_SECRETS_DIR="${MWAA_SECRETS_DIR:-/tmp/mwaa-local}"

# Fetch connections from Secrets Manager using local AWS credentials and write to
# a temp directory outside the repo, which is mounted read-only into the container.
# The secrets file is never written to the repo directory.
if [ -f "$ENV_FILE" ]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
fi

mkdir -p "$MWAA_SECRETS_DIR"
export MWAA_SECRETS_DIR

if [ -n "$CONNECTIONS_SECRET_ID" ]; then
    echo "==> Fetching connections from Secrets Manager (${CONNECTIONS_SECRET_ID})..."
    aws secretsmanager get-secret-value \
        --secret-id "$CONNECTIONS_SECRET_ID" \
        --region "${AWS_REGION:-us-east-2}" \
        --query SecretString \
        --output text > "$MWAA_SECRETS_DIR/connections.json"
    if [ $? -eq 0 ]; then
        echo "==> Connections written to ${MWAA_SECRETS_DIR}/connections.json"
    else
        echo "WARNING: Failed to fetch connections secret — connections will not be imported" >&2
        rm -f "$MWAA_SECRETS_DIR/connections.json"
    fi
else
    echo "==> CONNECTIONS_SECRET_ID not set — skipping connection fetch"
fi

# Sync plugins_whl.zip from S3 and extract wheels for pip --find-links
echo "==> Syncing plugins_whl.zip from S3..."
mkdir -p "$PLUGINS_DIR"
aws s3 sync "$PLUGINS_S3_DIR" "$PLUGINS_DIR/" --exclude '*' --include 'plugins_whl.zip'
echo "==> Extracting wheels..."
unzip -o "$PLUGINS_DIR/plugins_whl.zip" -d "$PLUGINS_DIR/" > /dev/null

# The DAGs volume name must match docker-compose.yaml
DAGS_VOLUME="mwaa-$(echo "$AIRFLOW_VERSION" | tr -d '.')-dags-volume"
SCHEDULER_CONTAINER="mwaa-$(echo "$AIRFLOW_VERSION" | tr -d '.')-scheduler"

# Initial sync: DAGs + requirements.txt
echo "==> Syncing from data-pipelines..."
MSYS_NO_PATHCONV=1 python sync_dags.py "$DATA_PIPELINES_DIR" "$AIRFLOW_VERSION"

# Pre-populate the named DAGs volume from the staged dags directory.
# This one-time copy via the 9P bridge is acceptable — the scheduler will
# subsequently read from the native ext4 volume, not the Windows filesystem.
echo "==> Populating DAGs volume (${DAGS_VOLUME})..."
MSYS_NO_PATHCONV=1 docker run --rm \
    -v "${DAGS_VOLUME}:/dags" \
    -v "$(pwd)/images/airflow/$AIRFLOW_VERSION/dags:/src:ro" \
    alpine sh -c "cp -a /src/. /dags/"

# Optionally keep syncing in the background while the stack runs
if [ "$WATCH" == "true" ]; then
    echo "==> Starting sync-dags in background (watch mode)..."
    MSYS_NO_PATHCONV=1 python sync_dags.py "$DATA_PIPELINES_DIR" "$AIRFLOW_VERSION" \
        --watch --docker-container "$SCHEDULER_CONTAINER" &
    SYNC_PID=$!
    trap "echo '==> Stopping sync-dags...'; kill $SYNC_PID 2>/dev/null; exit" INT TERM EXIT
fi

# Start the MWAA stack
echo "==> Starting MWAA stack (Airflow $AIRFLOW_VERSION)..."
cd "images/airflow/$AIRFLOW_VERSION"
./run.sh
