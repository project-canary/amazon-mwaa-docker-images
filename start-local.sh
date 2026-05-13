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
DATA_PIPELINES_DIR="${SYNC_ARGS[0]:-/c/Development/data-pipelines}"
AIRFLOW_VERSION="${SYNC_ARGS[1]:-2.10.3}"

# Sync plugins_whl.zip from S3 and extract wheels for pip --find-links
echo "==> Syncing plugins_whl.zip from S3..."
PLUGINS_DIR="images/airflow/$AIRFLOW_VERSION/plugins"
mkdir -p "$PLUGINS_DIR"
aws s3 sync s3://canary-etl-jobs/airflow/nonprod_2103/dependencies/ "$PLUGINS_DIR/" --exclude '*' --include 'plugins_whl.zip'
echo "==> Extracting wheels..."
unzip -o "$PLUGINS_DIR/plugins_whl.zip" -d "$PLUGINS_DIR/" > /dev/null

# Initial sync: DAGs + requirements.txt
echo "==> Syncing from data-pipelines..."
MSYS_NO_PATHCONV=1 python sync_dags.py "$DATA_PIPELINES_DIR" "$AIRFLOW_VERSION"

# Optionally keep syncing in the background while the stack runs
if [ "$WATCH" == "true" ]; then
    echo "==> Starting sync-dags in background (watch mode)..."
    MSYS_NO_PATHCONV=1 python sync_dags.py "$DATA_PIPELINES_DIR" "$AIRFLOW_VERSION" --watch &
    SYNC_PID=$!
    trap "echo '==> Stopping sync-dags...'; kill $SYNC_PID 2>/dev/null; exit" INT TERM EXIT
fi

# Start the MWAA stack
echo "==> Starting MWAA stack (Airflow $AIRFLOW_VERSION)..."
cd "images/airflow/$AIRFLOW_VERSION"
./run.sh
