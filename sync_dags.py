"""
Syncs DAGs from the local data-pipelines repository into the Airflow image dags directory,
mirroring the same layout used when deploying to S3.
"""

import argparse
import os
import re
import shutil
import sys
import time
from pathlib import Path


def resolve_path(p: str) -> Path:
    """Convert a Git Bash-style path (/c/foo) to a Windows path (C:/foo) if needed."""
    match = re.match(r'^/([a-zA-Z])/(.*)', p)
    if match:
        drive, rest = match.groups()
        return Path(f"{drive.upper()}:/{rest}")
    return Path(p)


REPO_TO_DAG_PATH_MAPPING = [
    ("aeris/airflow/dags/aeris/",                               "aeris"),
    ("aeroqual/airflow/dags/aeroqual/",                         "aeroqual"),
    ("arcgis/airflow/dags/arcgis_pc/",                          "arcgis_pc"),
    ("bi/airflow/dags/bi/",                                     "bi"),
    ("blackline/airflow/dags/blackline/",                       "blackline"),
    ("common/",                                                  "common"),
    ("data_hub/airflow/dags/nata_hub_api/",                     "nata_hub_api"),
    ("data_hub/airflow/dags/nata_hub/",                         "nata_hub"),
    ("digital_canopy/airflow/dags/periodic_monitoring/",        "periodic_monitoring"),
    ("executive_reporting/airflow/dags/executive_reporting/",   "executive_reporting"),
    ("kuva/airflow/dags/kuva/",                                 "kuva"),
    ("mapbox/airflow/dags/mapbox/",                             "mapbox"),
    ("markets/airflow/dags/markets/",                           "markets"),
    ("operations/airflow/dags/operations/",                     "operations"),
    ("planet/airflow/dags/planet/",                             "planet"),
    ("quandary/airflow/dags/quandary/",                         "quandary"),
    ("qube/airflow/dags/qube/",                                 "qube"),
    ("sense/airflow/dags/sense/",                               "sense"),
    ("sensirion/airflow/dags/sensirion/",                       "sensirion"),
    ("sensit/airflow/dags/sensit/",                             "sensit"),
    ("validere/airflow/dags/validere/",                         "validere"),
    ("well_database/airflow/dags/well_database/",               "well_database"),
]

EXCLUDE_DIRS = {"__pycache__"}
EXCLUDE_SUFFIXES = {".pyc"}


def get_snapshot(src: Path, extra_excludes: set[str] = set()) -> dict[Path, float]:
    """Recursively collect {path: mtime} for all relevant files under src."""
    snapshot = {}
    for item in src.rglob("*"):
        if any(p in EXCLUDE_DIRS or p in extra_excludes for p in item.parts):
            continue
        if item.suffix in EXCLUDE_SUFFIXES:
            continue
        if item.is_file():
            try:
                snapshot[item] = item.stat().st_mtime
            except OSError:
                pass
    return snapshot


def sync_dir(src: Path, dst: Path, extra_excludes: set[str] = set()):
    """Mirror src into dst, deleting files in dst that no longer exist in src."""
    dst.mkdir(parents=True, exist_ok=True)

    src_names = set()
    for item in src.iterdir():
        if item.name in EXCLUDE_DIRS or item.name in extra_excludes:
            continue
        if item.suffix in EXCLUDE_SUFFIXES:
            continue
        src_names.add(item.name)
        dst_item = dst / item.name
        if item.is_dir():
            sync_dir(item, dst_item, extra_excludes)
        else:
            if not dst_item.exists() or item.stat().st_mtime > dst_item.stat().st_mtime:
                shutil.copy2(item, dst_item)

    # Delete items in dst that are no longer in src
    for item in list(dst.iterdir()):
        if item.name not in src_names:
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()


REQUIREMENTS_SRC = "Terraform/images/codebuild_custom/requirements.txt"


def sync_requirements(data_pipelines_dir: Path, airflow_version: str, quiet: bool = False) -> list[str]:
    """Copy requirements.txt from data-pipelines into the Airflow requirements directory."""
    src = data_pipelines_dir / REQUIREMENTS_SRC
    dst = Path(f"images/airflow/{airflow_version}/requirements/requirements.txt")
    if not src.exists():
        return [] if quiet else [f"  skipped requirements.txt (not found at {src})"]
    shutil.copy2(src, dst)
    return [f"  synced {REQUIREMENTS_SRC} -> {dst}"]


def run_sync(data_pipelines_dir: Path, dags_dir: Path, quiet: bool = False):
    """Run a full sync of all DAG directories."""
    changed = []

    for src_rel, dst_name in REPO_TO_DAG_PATH_MAPPING:
        src = data_pipelines_dir / src_rel
        dst = dags_dir / dst_name
        if src.is_dir():
            sync_dir(src, dst)
            changed.append(f"  synced {src_rel} -> {dags_dir}/{dst_name}/")
        elif not quiet:
            changed.append(f"  skipped {src_rel} (not found)")

    # metec has an extra exclude
    src = data_pipelines_dir / "metec/airflow/dags/metec/"
    dst = dags_dir / "metec"
    if src.is_dir():
        sync_dir(src, dst, extra_excludes={"apply_data_models_factory.py"})
        changed.append(f"  synced metec/airflow/dags/metec/ -> {dags_dir}/metec/")
    elif not quiet:
        changed.append(f"  skipped metec (not found)")

    return changed


def build_watch_snapshot(data_pipelines_dir: Path) -> dict[Path, float]:
    """Build a snapshot of all watched source files."""
    snapshot = {}
    for src_rel, _ in REPO_TO_DAG_PATH_MAPPING:
        src = data_pipelines_dir / src_rel
        if src.is_dir():
            snapshot.update(get_snapshot(src))
    metec_src = data_pipelines_dir / "metec/airflow/dags/metec/"
    if metec_src.is_dir():
        snapshot.update(get_snapshot(metec_src, extra_excludes={"apply_data_models_factory.py"}))
    return snapshot


def main():
    parser = argparse.ArgumentParser(description="Sync DAGs from data-pipelines to the Airflow dags directory.")
    parser.add_argument("data_pipelines_dir", nargs="?", default="/c/Development/data-pipelines",
                        help="Path to the data-pipelines repository (default: /c/Development/data-pipelines)")
    parser.add_argument("airflow_version", nargs="?", default="2.10.3",
                        help="Airflow version to sync into (default: 2.10.3)")
    parser.add_argument("--watch", action="store_true",
                        help="Watch for changes and re-sync automatically")
    parser.add_argument("--interval", type=int, default=5,
                        help="Poll interval in seconds when using --watch (default: 5)")
    args = parser.parse_args()

    data_pipelines_dir = resolve_path(args.data_pipelines_dir)
    dags_dir = Path(f"images/airflow/{args.airflow_version}/dags")

    if not data_pipelines_dir.exists():
        print(f"Error: data-pipelines directory not found at '{data_pipelines_dir}'", file=sys.stderr)
        print(f"Usage: python sync_dags.py [path/to/data-pipelines] [airflow-version] [--watch]", file=sys.stderr)
        sys.exit(1)

    # Initial sync
    print(f"Syncing from '{data_pipelines_dir}'...")
    for line in sync_requirements(data_pipelines_dir, args.airflow_version):
        print(line)
    for line in run_sync(data_pipelines_dir, dags_dir):
        print(line)
    print("Done.")

    if not args.watch:
        return

    print(f"\nWatching for changes every {args.interval}s... (Ctrl+C to stop)\n")
    snapshot = build_watch_snapshot(data_pipelines_dir)

    while True:
        time.sleep(args.interval)
        new_snapshot = build_watch_snapshot(data_pipelines_dir)

        if new_snapshot != snapshot:
            print(f"[{time.strftime('%H:%M:%S')}] Changes detected, syncing...")
            for line in sync_requirements(data_pipelines_dir, args.airflow_version, quiet=True):
                print(line)
            for line in run_sync(data_pipelines_dir, dags_dir, quiet=True):
                print(line)
            print("Done.")
            snapshot = new_snapshot


if __name__ == "__main__":
    main()
