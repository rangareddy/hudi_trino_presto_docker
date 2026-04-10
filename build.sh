#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
STACK_ENV="${SCRIPT_DIR}/stack.env"
if [ ! -f "$STACK_ENV" ]; then
    echo "Missing ${STACK_ENV}" >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
source "$STACK_ENV"
set +a

export HUDI_VERSION_TAG="${HUDI_VERSION_TAG:-$HUDI_VERSION}"
export HIVE_VERSION_TAG="${HIVE_VERSION_TAG:-$HIVE_VERSION}"
export TRINO_VERSION_TAG="${TRINO_VERSION_TAG:-$TRINO_VERSION}"
export PRESTO_VERSION_TAG="${PRESTO_VERSION_TAG:-$PRESTO_VERSION}"

# Only the literal true (any case) counts as enabled — not 1, yes, on, etc.
env_is_true() {
    [ "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" = "true" ]
}

NOTEBOOK_STAGING="${SCRIPT_DIR}/build-notebooks"
rm -rf "$NOTEBOOK_STAGING"
mkdir -p "$NOTEBOOK_STAGING"
cp "${SCRIPT_DIR}/notebooks/utils.py" "$NOTEBOOK_STAGING/"
if env_is_true "${ENABLE_TRINO:-}"; then
    cp "${SCRIPT_DIR}/notebooks/hudi_trino_example.ipynb" "$NOTEBOOK_STAGING/"
fi
if env_is_true "${ENABLE_PRESTO:-}"; then
    cp "${SCRIPT_DIR}/notebooks/hudi_presto_example.ipynb" "$NOTEBOOK_STAGING/"
fi
echo "Spark image notebooks (from stack.env): $(ls -1 "$NOTEBOOK_STAGING" | tr '\n' ' ')"

echo "Building Spark Hudi Docker image using Spark version: $SPARK_VERSION and Hudi version: $HUDI_VERSION"

docker build \
    --build-arg HUDI_VERSION="$HUDI_VERSION" \
    --build-arg SPARK_VERSION="$SPARK_VERSION" \
    --build-arg JAVA_VERSION="$JAVA_VERSION" \
    --build-arg SCALA_VERSION="$SCALA_VERSION" \
    --build-arg HADOOP_VERSION="$HADOOP_VERSION" \
    --build-arg AWS_SDK_VERSION="$AWS_SDK_VERSION" \
    -t "$DOCKER_HUB_USERNAME"/spark-hudi:latest \
    -t "$DOCKER_HUB_USERNAME"/spark-hudi:"$HUDI_VERSION_TAG" \
    -f "$SCRIPT_DIR"/dockerfiles/Dockerfile.spark .

echo "Building Hive Docker image using Hive version: $HIVE_VERSION"

docker build \
    --platform "$TARGET_PLATFORM" \
    --build-arg HIVE_VERSION="$HIVE_VERSION" \
    -t "$DOCKER_HUB_USERNAME"/hive:latest \
    -t "$DOCKER_HUB_USERNAME"/hive:"$HIVE_VERSION_TAG" \
    -f "$SCRIPT_DIR"/dockerfiles/Dockerfile.hive .

if env_is_true "${ENABLE_TRINO:-}"; then
    echo "Building Trino Docker image using Trino version: $TRINO_VERSION"
    docker build \
        --build-arg JAVA_VERSION="$TRINO_JAVA_VERSION" \
        --build-arg HUDI_VERSION="$HUDI_VERSION" \
        --build-arg TRINO_VERSION="$TRINO_VERSION" \
        -t "$DOCKER_HUB_USERNAME"/trino:latest \
        -t "$DOCKER_HUB_USERNAME"/trino:"$TRINO_VERSION_TAG" \
        -f "$SCRIPT_DIR"/dockerfiles/Dockerfile.trino .
else
    echo "Skipping Trino image (set ENABLE_TRINO=true in stack.env to build)"
fi

if env_is_true "${ENABLE_PRESTO:-}"; then
    echo "Building Presto Docker image using Presto version: $PRESTO_VERSION"
    docker build \
        --build-arg JAVA_VERSION="$PRESTO_JAVA_VERSION" \
        --build-arg HUDI_VERSION="$HUDI_VERSION" \
        --build-arg PRESTO_VERSION="$PRESTO_VERSION" \
        -t "$DOCKER_HUB_USERNAME"/presto:latest \
        -t "$DOCKER_HUB_USERNAME"/presto:"$PRESTO_VERSION_TAG" \
        -f "$SCRIPT_DIR"/dockerfiles/Dockerfile.presto .
else
    echo "Skipping Presto image (set ENABLE_PRESTO=true in stack.env to build)"
fi

# Regenerate .env.compose after every successful build (COMPOSE_FILE from ENABLE_* in stack.env).
compose_files="docker-compose.yml"
if env_is_true "${ENABLE_TRINO:-}"; then
    compose_files="${compose_files}:docker-compose.trino.yml"
fi
if env_is_true "${ENABLE_PRESTO:-}"; then
    compose_files="${compose_files}:docker-compose.presto.yml"
fi
printf 'COMPOSE_FILE=%s\n' "$compose_files" >"${SCRIPT_DIR}/.env.compose"
echo "Wrote ${SCRIPT_DIR}/.env.compose"
echo "  COMPOSE_FILE=${compose_files}"
