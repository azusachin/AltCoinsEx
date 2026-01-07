#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE_PATH="${ROOT_DIR}/Dockerfile.litecoin"
IMAGE_NAME="altomake:litecoin"
CONTAINER_NAME="automeklitecoin"
HTTP_PROXY_DEFAULT="http://192.168.100.2:10810"
HTTPS_PROXY_DEFAULT="http://192.168.100.2:10810"
NO_PROXY_DEFAULT="localhost,127.0.0.1,::1,.aliyun.com,mirrors.aliyun.com"

HTTP_PROXY="${HTTP_PROXY:-${HTTP_PROXY_DEFAULT}}"
HTTPS_PROXY="${HTTPS_PROXY:-${HTTPS_PROXY_DEFAULT}}"
NO_PROXY="${NO_PROXY:-${NO_PROXY_DEFAULT}}"

pick_output_dir() {
  local base="${ROOT_DIR}/output"
  if [[ ! -e "${base}" ]]; then
    echo "${base}"
    return
  fi
  local index=1
  while :; do
    local candidate
    printf -v candidate "%s%02d" "${base}" "${index}"
    if [[ ! -e "${candidate}" ]]; then
      echo "${candidate}"
      return
    fi
    index=$((index + 1))
  done
}

create_dockerfile() {
  cat > "${DOCKERFILE_PATH}" <<'EOF'
FROM ubuntu:18.04

ARG http_proxy
ARG https_proxy
ARG no_proxy

ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}
ENV no_proxy=${no_proxy}
ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list \
    && sed -i 's|http://security.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libtool \
        autotools-dev \
        automake \
        pkg-config \
        bsdmainutils \
        curl \
        git \
        ca-certificates \
        python3 \
        g++-mingw-w64-x86-64 \
        nsis \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/litecoin
COPY . /opt/litecoin

RUN cd /opt/litecoin/depends \
    && make HOST=x86_64-w64-mingw32 \
    && make HOST=x86_64-pc-linux-gnu

ENV DEPENDS_DIR=/opt/litecoin/depends
EOF
}

build_image() {
  docker build \
    --build-arg http_proxy="${HTTP_PROXY}" \
    --build-arg https_proxy="${HTTPS_PROXY}" \
    --build-arg no_proxy="${NO_PROXY}" \
    -f "${DOCKERFILE_PATH}" \
    -t "${IMAGE_NAME}" \
    "${ROOT_DIR}"
}

run_build_container() {
  local output_dir="$1"
  mkdir -p "${output_dir}"
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi

  docker run --name "${CONTAINER_NAME}" --rm \
    -e http_proxy="${HTTP_PROXY}" \
    -e https_proxy="${HTTPS_PROXY}" \
    -e no_proxy="${NO_PROXY}" \
    -v "${ROOT_DIR}:/workspace/litecoin" \
    -v "${output_dir}:/output" \
    "${IMAGE_NAME}" \
    bash -euxo pipefail -c '
      cd /workspace/litecoin
      export DEPENDS_DIR=/opt/litecoin/depends

      mkdir -p build-linux
      cd build-linux
      ../autogen.sh
      CONFIG_SITE="${DEPENDS_DIR}/x86_64-pc-linux-gnu/share/config.site" ../configure --prefix=/
      make -j"$(nproc)"

      cd /workspace/litecoin
      mkdir -p build-win
      cd build-win
      ../autogen.sh
      CONFIG_SITE="${DEPENDS_DIR}/x86_64-w64-mingw32/share/config.site" ../configure --prefix=/ --host=x86_64-w64-mingw32
      make -j"$(nproc)"

      mkdir -p /output
      cp -v build-linux/src/acecnd /output/
      cp -v build-linux/src/litecoin-cli /output/
      cp -v build-linux/src/litecoin-tx /output/
      cp -v build-linux/src/qt/litecoin-qt /output/
      cp -v build-win/src/acecnd.exe /output/
      cp -v build-win/src/litecoin-cli.exe /output/
      cp -v build-win/src/litecoin-tx.exe /output/
      cp -v build-win/src/qt/litecoin-qt.exe /output/
    '
}

main() {
  echo "Step 1: Generating ${DOCKERFILE_PATH}"
  create_dockerfile
  echo "Step 1: Building Docker image ${IMAGE_NAME}"
  build_image

  echo "Step 2: Running container ${CONTAINER_NAME} to build wallets"
  output_dir="$(pick_output_dir)"
  echo "Step 2: Output directory is ${output_dir}"
  run_build_container "${output_dir}"
  echo "Build artifacts copied to ${output_dir}"
}

main "$@"
