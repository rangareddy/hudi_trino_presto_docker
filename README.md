<!--
  Licensed to the Apache Software Foundation (ASF) under one or more
  contributor license agreements.  See the NOTICE file distributed with
  this work for additional information regarding copyright ownership.
  The ASF licenses this file to You under the Apache License, Version 2.0
  (the "License"); you may not use this file except in compliance with
  the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-->

# Spark, Hudi, Trino, Presto, Hive Metastore, and MinIO (Docker Compose)

This repository builds four custom images—**Spark + Hudi + Jupyter**, **Hive Metastore**, **Trino**, and **Presto (PrestoDB)**—and runs them with **MinIO** (S3-compatible storage) via Docker Compose. Use it to develop and test Hudi tables on object storage and query them through **Trino** and/or **Presto** using the Hive Metastore. Presto uses the **Hive Hadoop2** connector plus optional **custom JARs** (for example the Apache Hudi **Presto** bundle and any extras under `jars/presto/plugin-hive/`).

## What runs in Compose

| Service | Image (default tag prefix) | Role |
|--------|----------------------------|------|
| `spark-hudi` | `$DOCKER_HUB_USERNAME/spark-hudi:latest` | Spark master/worker, History Server, Jupyter Notebook; Hudi Spark bundle; configs under `conf/spark/` |
| `hive-metastore` | `$DOCKER_HUB_USERNAME/hive:latest` | Hive Metastore (Thrift); `conf/hive/metastore-site.xml` baked into the image |
| `minio` | `minio/minio:latest` | S3 API and console; data under `./data/minio` |
| `mc` | `minio/mc:latest` | One-shot bucket setup: creates `warehouse` and sets a public policy (depends on healthy MinIO) |
| `trino` | `$DOCKER_HUB_USERNAME/trino:latest` | Trino coordinator; Hudi and Hive catalogs pointing at Metastore and MinIO (`conf/trino/catalog/`) |
| `presto` | `$DOCKER_HUB_USERNAME/presto:latest` | PrestoDB coordinator; Hive catalog with MinIO + Metastore (`conf/presto/catalog/`); custom JARs from `jars/presto/` |

Default image namespace: `DOCKER_HUB_USERNAME=apachehuditrino` (override when building or running Compose).

## Repository layout

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | Service definitions, ports, networks, MinIO credentials |
| `build.sh` | Builds Spark, Hive, Trino, and Presto images (`-f dockerfiles/Dockerfile.*`, context = repo root) |
| `run_spark_trino_hudi.sh` | `start` \| `stop` \| `restart` the stack (uses `docker compose` or `docker-compose`) |
| `dockerfiles/Dockerfile.spark` | Spark image: Hudi bundle, AWS SDK jars, notebooks, `entrypoint.sh` |
| `dockerfiles/Dockerfile.hive` | Hive Metastore image (`linux/amd64` in `build.sh`) |
| `dockerfiles/Dockerfile.trino` | Trino image: server tarball, CLI, optional `hudi-trino-bundle`, JMX Prometheus agent |
| `dockerfiles/Dockerfile.presto` | PrestoDB image: `presto-server` tarball from `jars/presto/`, optional `hudi-presto-bundle-*.jar`, optional `plugin-hive/*.jar` |
| `entrypoint.sh` | Spark container: master, worker, history server, Jupyter on port 8888 |
| `requirements.txt` | Python deps for the Spark image (includes `trino`, `presto-python-client`, `boto3`, `jupyter`, etc.) |
| `conf/spark/` | `spark-defaults.conf`, `hudi-defaults.conf` |
| `conf/hive/metastore-site.xml` | Metastore configuration |
| `conf/trino/catalog/` | Trino `etc` and catalog files (`hive.properties`, `hudi.properties`, `jvm.config`, …) |
| `conf/presto/catalog/` | Presto `etc` and catalog files (`hive.properties` uses `hive-hadoop2`, `jvm.config`, …) |
| `notebooks/` | Copied into the Spark image; examples `hudi_trino_example.ipynb`, `hudi_presto_example.ipynb`, and `utils.py` |
| `jars/` | **Local-only** build inputs (ignored by Git—see `.gitignore`) |

## Prerequisites

- Docker with Compose (`docker compose` or `docker-compose`)
- JARs and archives placed under `jars/` before `./build.sh` (see below)

### `jars/` layout for `build.sh`

**Spark / Hudi** (`dockerfiles/Dockerfile.spark`):

- `jars/hudi/hudi-spark<SPARK_MINOR>-bundle_<SCALA>-<HUDI_VERSION>.jar`  
  Example defaults from `build.sh`: Spark `3.4.4` → minor `3.4`, Scala `2.12`, Hudi `0.14.2-SNAPSHOT` →  
  `jars/hudi/hudi-spark3.4-bundle_2.12-0.14.2-SNAPSHOT.jar`

**Trino** (`dockerfiles/Dockerfile.trino`):

- `jars/trino/trino-server-<TRINO_VERSION>.tar` (extractable tarball; **not** `.tar.gz` in the current Dockerfile)
- `jars/trino/trino-cli-<TRINO_VERSION>-executable.jar`
- Optional: `jars/trino/hudi-trino-bundle-*.jar` — if present, default Hudi JARs in Trino’s `hudi` and `hive` plugins are replaced

**Presto / PrestoDB** (`dockerfiles/Dockerfile.presto`):

- `jars/presto/presto-server-<PRESTO_VERSION>.tar.gz` (for example from [Maven Central](https://repo1.maven.org/maven2/com/facebook/presto/presto-server/) `com.facebook.presto:presto-server`)
- Optional: `jars/presto/hudi-presto-bundle-*.jar` — copied into `plugin/hive` after removing existing `hudi-*.jar` in that directory (same idea as the Hudi Presto integration docs)
- Optional: `jars/presto/plugin-hive/*.jar` — any additional JARs merged into `plugin/hive` (dependency overrides, connectors, or bundles)

Default `TRINO_VERSION` in `build.sh` is `449`. Default Trino JDK build arg is `TRINO_JAVA_VERSION=22` (`JAVA_VERSION` passed as `--build-arg` to `dockerfiles/Dockerfile.trino`).

Default `PRESTO_VERSION` is `0.287` with `PRESTO_JAVA_VERSION=17` for the Presto image base JDK.

Build context for every image is the **repository root** (`.`); paths like `conf/` and `jars/` in the Dockerfiles are relative to that root.

## Build images

From the repo root:

```sh
chmod +x build.sh run_spark_trino_hudi.sh
bash build.sh
```

Useful environment variables (all optional; defaults are set inside `build.sh`):

| Variable | Role |
|----------|------|
| `DOCKER_HUB_USERNAME` | Image name prefix for all four custom images (default `apachehuditrino`) |
| `HUDI_VERSION` / `HUDI_VERSION_TAG` | Hudi version for Spark image tags and bundle file name |
| `SPARK_VERSION` | Spark version (must match the Hudi bundle naming) |
| `HIVE_VERSION` / `HIVE_VERSION_TAG` | Hive image version and tags |
| `TRINO_VERSION` / `TRINO_VERSION_TAG` | Trino distribution version and image tags |
| `TRINO_JAVA_VERSION` | Base JDK tag for Trino image (`eclipse-temurin:<ver>-jdk-jammy`) |
| `PRESTO_VERSION` / `PRESTO_VERSION_TAG` | PrestoDB server tarball version and image tags |
| `PRESTO_JAVA_VERSION` | Base JDK tag for the Presto image (defaults to `17`; align with your Presto release) |
| `JAVA_VERSION`, `SCALA_VERSION`, `HADOOP_VERSION`, `AWS_SDK_VERSION` | Spark image build args |

Example:

```sh
export DOCKER_HUB_USERNAME=myrepo
export TRINO_VERSION=449
export PRESTO_VERSION=0.287
export HUDI_VERSION=0.14.2-SNAPSHOT
bash build.sh
```

Manual builds (same context and Dockerfiles as `build.sh`):

```sh
docker build -f dockerfiles/Dockerfile.spark -t myrepo/spark-hudi:latest .
docker build --platform linux/amd64 -f dockerfiles/Dockerfile.hive -t myrepo/hive:latest .
docker build -f dockerfiles/Dockerfile.trino --build-arg TRINO_VERSION=449 --build-arg JAVA_VERSION=22 -t myrepo/trino:latest .
docker build -f dockerfiles/Dockerfile.presto --build-arg PRESTO_VERSION=0.287 --build-arg JAVA_VERSION=17 -t myrepo/presto:latest .
```

## Run the stack

Ensure `DOCKER_HUB_USERNAME` matches the prefix you used when building (Compose reads it from the environment):

```sh
export DOCKER_HUB_USERNAME=apachehuditrino   # or your custom prefix
./run_spark_trino_hudi.sh start
```

Other commands:

```sh
./run_spark_trino_hudi.sh stop
./run_spark_trino_hudi.sh restart   # down then up -d --build
```

Compose references pre-built image names only (no `build:` blocks). Re-run `./build.sh` when you change files under `dockerfiles/` or `jars/` contents; `restart` mainly recreates containers from the current local tags.

## Service URLs and ports

| Service | URL / endpoint | Notes |
|---------|----------------|--------|
| Jupyter | http://localhost:8888 | Token/password disabled in `entrypoint.sh` (local dev only) |
| Spark UI (driver) | http://localhost:14040 | Host port mapped to container `4040` |
| Spark Master UI | http://localhost:8080 | |
| Spark Worker UI | http://localhost:8081 | |
| Spark History Server | http://localhost:18080 | |
| MinIO S3 API | http://localhost:9000 | Keys in Compose: `admin` / `password` |
| MinIO Console | http://localhost:9001 | Same credentials |
| Hive Metastore | `thrift://localhost:9083` | |
| Trino Web UI / JDBC | http://localhost:8085 | Mapped to container `8080` |
| Presto Web UI / JDBC | http://localhost:8086 | Mapped to container `8080`; metrics agent on **9092** (host `9092` if needed) |

Inside the Docker network, Spark, Trino, and Presto use `http://minio:9000`, `thrift://hive-metastore:9083`, and the `warehouse.minio` alias for virtual-host style paths where configured. From the **Spark** container, Presto is reachable at `presto:8080` (see `hudi_presto_example.ipynb` for `PRESTO_HOST` / `PRESTO_PORT`). From the **host**, use `localhost:8086`.

## Configuration notes

- **Spark / Hudi**: `conf/spark/` is copied into `$SPARK_HOME/conf/` in the Spark image.
- **Hive**: `conf/hive/metastore-site.xml` is copied into the Hive image; Metastore uses Derby by default (fine for demos; use MySQL/Postgres for production-like setups).
- **Trino**: Catalogs under `conf/trino/catalog/` are baked in. `jvm.config` references the JMX Prometheus agent and `config.yaml`. Adjust memory and ports there if needed, then rebuild.
- **Presto**: Catalogs under `conf/presto/catalog/` are baked in. The Hive catalog uses `connector.name=hive-hadoop2` and `hive.s3.*` settings for MinIO. JMX Prometheus in `conf/presto/catalog/jvm.config` listens on container port **9092** (`/opt/presto-jmx-config.yaml`). After changing JVM or catalog settings, rebuild the Presto image.

## Example notebooks

- `notebooks/hudi_trino_example.ipynb` — Spark write + Trino query walkthrough.
- `notebooks/hudi_presto_example.ipynb` — Spark write + Presto query walkthrough (includes inline `prestodb` connection setup).
- `notebooks/utils.py` — shared Spark helpers (`get_spark_session`, `display`, etc.).

## Cleanup

```sh
./run_spark_trino_hudi.sh stop
docker compose down -v   # or docker-compose down -v
```

`-v` removes named volumes if you add any later; local bind mounts under `./data/` remain on disk unless you delete them manually.

## References

- [Apache Hudi](https://hudi.apache.org/)
- [Spark quick start (Hudi)](https://hudi.apache.org/docs/quick-start-guide/)
- [Trino](https://trino.io/)
- [PrestoDB](https://prestodb.io/)

## Contributing

See the [Hudi contribution guide](https://hudi.apache.org/contribute/how-to-contribute) and [developer setup](https://hudi.apache.org/contribute/developer-setup) for upstream Hudi contributions.
