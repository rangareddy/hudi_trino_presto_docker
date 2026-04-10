# Spark, Hudi, Trino, Presto, Hive Metastore, and MinIO (Docker Compose)

This repository builds **Spark + Hudi + Jupyter**, **Hive Metastore**, **Trino**, and **Presto (PrestoDB)** images and runs them with **MinIO** via Docker Compose. Use it to develop and test Hudi tables on object storage and query them through **Trino** (`hudi` catalog for Hudi tables) and/or **Presto** (Hive / `hive-hadoop2` plus Hudi Presto bundle). Defaults and toggles live in **`stack.env`**.

## What runs in Compose

Core services live under **`compose/docker-compose.yml`**. **Trino** and **Presto** use **`compose/docker-compose.trino.yml`** / **`compose/docker-compose.presto.yml`** when **`ENABLE_TRINO`** / **`ENABLE_PRESTO`** are `true` in **`stack.env`**. **`build.sh`** and **`run_spark_trino_presto_hudi.sh`** write **`.env.compose`** (`COMPOSE_FILE=...` with paths under `compose/`; gitignored). Run Compose from the **repository root**.

| Service | Image (default tag prefix) | Role |
|--------|----------------------------|------|
| `spark-hudi` | `$DOCKER_HUB_USERNAME/spark-hudi:latest` | Spark, History Server, Jupyter; `conf/spark/` |
| `hive-metastore` | `$DOCKER_HUB_USERNAME/hive:latest` | Hive Metastore (Thrift); `conf/hive/metastore-site.xml` |
| `minio` | `minio/minio:latest` | S3 API and console; data under `./data/minio` |
| `mc` | `minio/mc:latest` | Bucket bootstrap for `warehouse` |
| `trino` | `$DOCKER_HUB_USERNAME/trino:latest` | Optional; catalogs in `conf/trino/catalog/` |
| `presto` | `$DOCKER_HUB_USERNAME/presto:latest` | Optional; catalogs in `conf/presto/catalog/` |

## Repository layout

| Path | Purpose |
|------|---------|
| `stack.env` | **Canonical defaults**: versions, `DOCKER_HUB_USERNAME`, `ENABLE_TRINO`, `ENABLE_PRESTO`, `TARGET_PLATFORM`, … |
| `compose/docker-compose.yml` | Spark, MinIO, `mc`, Hive Metastore |
| `compose/docker-compose.trino.yml` / `compose/docker-compose.presto.yml` | Query engine fragments (merged per `ENABLE_*`) |
| `build.sh` | Sources `stack.env`, stages `build-notebooks/` from `ENABLE_*`, builds images, writes `.env.compose` |
| `build-notebooks/` | Gitignored staging dir: `utils.py` plus `hudi_trino_example.ipynb` / `hudi_presto_example.ipynb` when the matching engine is enabled |
| `run_spark_trino_presto_hudi.sh` | Sources `stack.env`, writes `.env.compose`, then `start` \| `stop` \| `restart` |
| `dockerfiles/Dockerfile.*` | Image definitions |
| `entrypoint.sh` | Spark container entrypoint |
| `requirements.txt` | Python deps for the Spark image |
| `conf/` | Spark, Hive, Trino, Presto configuration |
| `notebooks/` | Source notebooks; **`build.sh`** copies a subset into **`build-notebooks/`** for `Dockerfile.spark` |
| `jars/` | Local build inputs only (gitignored) |

## Prerequisites

- Docker with Compose (`docker compose` or `docker-compose`)
- Contents under `jars/` as required below (paths use versions from **`stack.env`**)

### `jars/` layout

**Spark / Hudi** (`dockerfiles/Dockerfile.spark`):

- `jars/hudi/hudi-spark<SPARK_MINOR>-bundle_<SCALA>-<HUDI_VERSION>.jar`  
  Example with defaults in `stack.env` (Spark `3.4.4`, Scala `2.12`, Hudi `0.15.0-SNAPSHOT`):  
  `jars/hudi/hudi-spark3.4-bundle_2.12-0.15.0-SNAPSHOT.jar`

**Trino** (`dockerfiles/Dockerfile.trino`):

- `jars/trino/trino-server-<TRINO_VERSION>.tar` **or** `.tar.gz` (Dockerfile prefers `.tar.gz` if both are present)
- `jars/trino/trino-cli-<TRINO_VERSION>-executable.jar`
- Optional: `jars/trino/hudi-trino-bundle-*.jar` — replaces stock `hudi-trino-bundle*.jar` in Trino’s `hudi` and `hive` plugins

**Presto** (`dockerfiles/Dockerfile.presto`):

- `jars/presto/presto-server-<PRESTO_VERSION>.tar` **or** `.tar.gz` (Dockerfile prefers `.tar.gz` if both are present)
- `jars/presto/presto-cli-<PRESTO_VERSION>-executable.jar`
- `jars/presto/hudi-presto-bundle-<HUDI_VERSION>.jar` — must match **`HUDI_VERSION`** in `stack.env` (copied into `plugin/hudi` and the Hive plugin dir)

Build context for every image is the **repository root** (`.`).

## Build images

```sh
chmod +x build.sh run_spark_trino_presto_hudi.sh
bash build.sh
```

- Edit **`stack.env`** for versions and `ENABLE_TRINO` / `ENABLE_PRESTO`. Each engine runs only when its value is the literal **`true`** (case-insensitive); use **`false`** or any other value to disable.
Environment variables are defined in **`stack.env`**. To refresh **`.env.compose`** without rebuilding images, run **`./run_spark_trino_presto_hudi.sh start`** (or any run-script command), which re-reads `stack.env` and rewrites `.env.compose` before Compose runs.

Edit **`stack.env`** to change defaults; exporting variables in your shell before the scripts run does not override **`stack.env`**.

Manual `docker build` for Spark: **`Dockerfile.spark` expects `build-notebooks/`** (same layout as `./build.sh` creates). Either run **`./build.sh`** for the Spark step, or stage by hand, for example:

```sh
mkdir -p build-notebooks && cp notebooks/utils.py build-notebooks/
docker build -f dockerfiles/Dockerfile.spark \
  --build-arg HUDI_VERSION=0.15.0-SNAPSHOT --build-arg SPARK_VERSION=3.4.4 \
  --build-arg JAVA_VERSION=11 --build-arg SCALA_VERSION=2.12 \
  --build-arg HADOOP_VERSION=3.3.4 --build-arg AWS_SDK_VERSION=1.12.772 \
  -t myrepo/spark-hudi:latest .
docker build --platform linux/amd64 -f dockerfiles/Dockerfile.hive \
  --build-arg HIVE_VERSION=3.1.3 -t myrepo/hive:latest .
docker build -f dockerfiles/Dockerfile.trino \
  --build-arg TRINO_VERSION=450 --build-arg JAVA_VERSION=22 --build-arg HUDI_VERSION=0.15.0-SNAPSHOT \
  -t myrepo/trino:latest .
docker build -f dockerfiles/Dockerfile.presto \
  --build-arg PRESTO_VERSION=0.296 --build-arg JAVA_VERSION=17 --build-arg HUDI_VERSION=0.15.0-SNAPSHOT \
  -t myrepo/presto:latest .
```

## Run the stack

The run script loads **`stack.env`**, regenerates **`.env.compose`**, then runs Compose.

```sh
bash run_spark_trino_presto_hudi.sh start
bash run_spark_trino_presto_hudi.sh stop
bash run_spark_trino_presto_hudi.sh restart   # down then up -d --build
```

Ensure **`DOCKER_HUB_USERNAME`** in `stack.env` matches the tag prefix you used when building.

## Service URLs and ports

| Service | URL / endpoint | Notes |
|---------|----------------|--------|
| Jupyter | http://localhost:8888 | Local dev settings in `entrypoint.sh` |
| Spark UI (driver) | http://localhost:14040 | Host → container `4040` |
| Spark Master UI | http://localhost:8080 | |
| Spark Worker UI | http://localhost:8081 | |
| Spark History Server | http://localhost:18080 | |
| MinIO S3 API | http://localhost:9000 | Compose: `admin` / `password` |
| MinIO Console | http://localhost:9001 | |
| Hive Metastore | `thrift://localhost:9083` | |
| Trino | http://localhost:8085 | → container `8080`; use **`hudi`** catalog for Hudi tables |
| Presto | http://localhost:8086 | → container `8080`; JMX agent on **9092** in container |

Inside the Compose network, Spark/Trino/Presto use `http://minio:9000` and `thrift://hive-metastore:9083`. From the Spark container, Presto is `presto:8080`; from the host, Presto is `localhost:8086`.

## Configuration notes

- **Spark / Hudi**: `conf/spark/` is copied into the Spark image.
- **Hive**: `conf/hive/metastore-site.xml`; embedded Derby is fine for demos.
- **Trino**: `conf/trino/catalog/`. Query Hudi-backed tables through the **`hudi`** catalog, not **`hive`**.
- **Presto**: `conf/presto/catalog/`; primary connector is **`hive-hadoop2`** with `hive.s3.*` for MinIO.

## Example notebooks

Sources live under **`notebooks/`**. The Spark image receives **`notebooks/utils.py` always**, plus **`hudi_trino_example.ipynb`** when **`ENABLE_TRINO=true`** and **`hudi_presto_example.ipynb`** when **`ENABLE_PRESTO=true`** (`stack.env`), via **`build-notebooks/`** during **`./build.sh`**.

## Cleanup

```sh
bash run_spark_trino_presto_hudi.sh stop
docker compose down -v   # or docker-compose down -v
```

`-v` drops named volumes; bind mounts under `./data/` stay until you delete them.

## References

- [Apache Hudi](https://hudi.apache.org/)
- [Trino](https://trino.io/)
- [PrestoDB](https://prestodb.io/)

## Contributing

See the [Hudi contribution guide](https://hudi.apache.org/contribute/how-to-contribute) for upstream Hudi work.
