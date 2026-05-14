## aws-mwaa-docker-images

## Overview

This repository contains the Docker Images that [Amazon
MWAA](https://aws.amazon.com/managed-workflows-for-apache-airflow/) uses to run Airflow.

You can also use it locally if you want to run a MWAA-like environment for testing, experimentation,
and development purposes.

Currently, Airflow v2.9.2 and above are supported. Future versions in parity with Amazon MWAA will be added as
well. _Notice, however, that we do not plan to support previous Airflow versions supported by MWAA._

## Using the Airflow Image

### Prerequisites

- Python 3.11 or later — install from [python.org](https://www.python.org/downloads/) (check "Add Python to PATH" during install)
- [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/) set to **Linux containers** mode
  - Right-click the Docker Desktop tray icon → "Switch to Linux containers" if needed
- [Git for Windows](https://git-scm.com/download/win) (Git Bash) — used to run all shell commands
- AWS CLI (optional — only required if you want CloudWatch log group creation)

### One-time setup

1. Clone this repository.

2. Disable `autocrlf` globally — the `.gitattributes` handles line endings and `autocrlf` conflicts with it, causing spurious Dockerfile diffs. The Git for Windows installer sets this to `true` at the system level; override it at the global level so editors (e.g. VS Code) also respect it:

```bash
git config --global core.autocrlf false
```

3. Open **Git Bash** and create the Python virtual environments from the repo root:

```bash
# Create venv for a specific Airflow version only (recommended)
python create_venvs.py --target development --version 2.10.3

# Or create venvs for all Airflow versions
python create_venvs.py --target development
```

### Running

3. Navigate to an Airflow version directory and run the stack:

```bash
cd images/airflow/<version>
./run.sh
```

This will build the Docker images and start the full Airflow stack. On first run, the image build can take 10–20 minutes.

- To test a `requirements.txt` without running Airflow:
```bash
./run.sh test-requirements
```
- To test a `startup.sh` without running Airflow:
```bash
./run.sh test-startup-script
```

### AWS Credentials

For local development without a real AWS account, `run.sh` defaults to dummy values — ElasticMQ (the local SQS mock) does not validate credentials. To use real AWS services (e.g. CloudWatch logging), update `ACCOUNT_ID`, `ENV_NAME`, and the `AWS_*` variables at the top of `run.sh`.

### Logging in

Once the stack is up, open `http://localhost:8080`. The default credentials are printed in the webserver container logs on startup.

### Adding DAGs

DAGs are synced from the `data-pipelines` repository using `sync-dags.sh`, which mirrors the same directory layout used when deploying to S3 (matching production MWAA).

In a separate terminal, run from the repo root:

```bash
# One-time sync
./sync-dags.sh

# Watch mode — re-syncs automatically when files change (recommended during development)
./sync-dags.sh --watch

# Custom paths
./sync-dags.sh /path/to/data-pipelines 2.10.3 --watch
```

The default poll interval is 5 seconds. DAGs are picked up by Airflow within ~30 seconds of a sync.

### Stopping

Press `Ctrl+C` in the terminal where `./run.sh` is running — this gracefully stops all containers.

If you ran the stack detached (`-d`), stop it with:

```bash
docker compose down
```

### Troubleshooting

| Problem | Fix |
|---|---|
| `Docker is not in Linux containers mode` | Right-click Docker Desktop tray icon → Switch to Linux containers |
| `python` not found | Install Python 3.11+ from python.org with "Add to PATH" checked |
| `Unable to locate credentials` | Ensure `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are non-empty in `run.sh` |
| Login fails at `http://localhost:8080` | Check the webserver container logs for the credentials printed on startup |
| DAG not appearing | Check the scheduler container logs or verify the file exists in the `dags/` folder |
| Dockerfiles (or other files) show spurious line-ending diffs | Run `git config --global core.autocrlf false` then `git checkout -- .` to restore files |

### Authentication from version 3.0.1 onward
For environments created using this repository starting with version 3.0.1, we default to using `SimpleAuthManager`,
which is also the default auth manager in Airflow 3.0.0+. By default, `SIMPLE_AUTH_MANAGER_ALL_ADMINS` is set to true,
which means no username/password is required, and all users will have admin access. You can specify users and roles
using the SIMPLE_AUTH_MANAGER_USERS environment variable in the format:
```
username:role[,username2:role2,...]
```
To enforce authentication with explicit user passwords and roles, set:

```
SIMPLE_AUTH_MANAGER_ALL_ADMINS=false
```
In this mode, a password will be automatically generated for each user and printed in the webserver logs as soon as
webserver starts.


### Generated Docker Images

When you build the Docker images of a certain Airflow version, using either `build.sh` or `run.sh`
(which automatically also calls `build.sh` for you), multiple Docker images will actually be
generated. For example, for Airflow 2.9, you will notice the following images:

| Repository                        | Tag                           |
| --------------------------------- | ----------------------------- |
| amazon-mwaa-docker-images/airflow | 2.9.2                         |
| amazon-mwaa-docker-images/airflow | 2.9.2-dev                     |
| amazon-mwaa-docker-images/airflow | 2.9.2-explorer                |
| amazon-mwaa-docker-images/airflow | 2.9.2-explorer-dev            |
| amazon-mwaa-docker-images/airflow | 2.9.2-explorer-privileged     |
| amazon-mwaa-docker-images/airflow | 2.9.2-explorer-privileged-dev |

Each of the postfixes added to the image tag represents a certain build type, as explained below:

- `explorer`: The 'explorer' build type is almost identical to the default build type except that it
  doesn't include an entrypoint, meaning that if you run this image locally, it will not actually
  start Airflow. This is useful for debugging purposes to run the image and look around its content
  without starting airflow. For example, you might want to explore the file system and see what is
  available where.
- `privileged`: Privileged images are the same as their non-privileged counterpart except that they
  run as the `root` user instead. This gives the user of this Docker image
  elevated permissions. This can be useful if the user wants to do some experiments as the root
  user, e.g. installing DNF packages, creating new folders outside the airflow user folder, among
  others.
- `dev`: These images have extra packages installed for debugging purposes. For example, typically
  you wouldn't want to install a text editor in a Docker image that you use for production. However,
  during debugging, you might want to open some files and inspect their contents, make some changes,
  etc. Thus, we install an editor in the dev images to aid with such use cases. Similarly, we
  install tools like `wget` to make it possible for the user to fetch web pages. For a complete
  listing of what is installed in `dev` images, see the `bootstrap-dev` folders.


## Extra commands

#### Requirements

For details on installing Python depedencies, and optionally bundling wheel files, see the [Managing Python dependencies in requirements.txt](https://docs.aws.amazon.com/mwaa/latest/userguide/best-practices-dependencies.html#best-practices-dependencies-different-ways) in the Amazon MWAA user guide.

- Add Python dependencies to `requirements/requirements.txt`
- To test a `requirements.txt` without running Apache Airflow, run:
```bash
./run.sh test-requirements
```

#### Startup script

- There is a folder in each airflow version called `startup_script`. Add your script there as `startup.sh`
- If there is a need to run additional setup (e.g. install system libraries, setting up environment variables), please modify the `startup.sh` script.
- To test a `startup.sh` without running Apache Airflow, run:
```bash
./run.sh  test-startup-script
```

#### Reset database

- If you encountered [the following error](https://issues.apache.org/jira/browse/AIRFLOW-3678): `process fails with "dag_stats_table already exists"`, you'll need to reset your database. You just need to restart your container by exiting and rerunning the `run.sh` script

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.
