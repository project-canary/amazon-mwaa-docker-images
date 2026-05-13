#!/bin/bash
# Syncs DAGs from the local data-pipelines repository into the Airflow image dags directory,
# mirroring the same layout used when deploying to S3.
#
# Usage:
#   ./sync-dags.sh                          # one-time sync with defaults
#   ./sync-dags.sh --watch                  # watch mode, re-syncs on changes
#   ./sync-dags.sh /path/to/data-pipelines 2.10.3 --watch
set -e

if [ "$(basename "$PWD")" != "amazon-mwaa-docker-images" ]; then
    echo "Error: must be run from the amazon-mwaa-docker-images repo root" >&2
    exit 1
fi

MSYS_NO_PATHCONV=1 python sync_dags.py "$@"
