#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="lite-qt-exe-ok:latest"
CONTAINER_NAME="2tabchat"
REPO_URL_DEFAULT="https://github.com/litecoin-project/litecoin.git"

WORK_DIR="${PWD}"
REPO_URL="${REPO_URL:-${REPO_URL_DEFAULT}}"
BRANCH_NAME="${BRANCH_NAME:-codex/add-website-content-display-in-site-tab}"
HTTP_PROXY_DEFAULT="http://192.168.100.2:10810"
HTTPS_PROXY_DEFAULT="http://192.168.100.2:10810"
NO_PROXY_DEFAULT="localhost,127.0.0.1,::1,.tsinghua.edu.cn,mirrors.tuna.tsinghua.edu.cn"

HTTP_PROXY="${HTTP_PROXY:-${HTTP_PROXY_DEFAULT}}"
HTTPS_PROXY="${HTTPS_PROXY:-${HTTPS_PROXY_DEFAULT}}"
NO_PROXY="${NO_PROXY:-${NO_PROXY_DEFAULT}}"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

docker run -d \
  --name "${CONTAINER_NAME}" \
  -e http_proxy="${HTTP_PROXY}" \
  -e https_proxy="${HTTPS_PROXY}" \
  -e no_proxy="${NO_PROXY}" \
  -v "${WORK_DIR}:/work" \
  "${IMAGE_NAME}" \
  sleep infinity

docker exec -e http_proxy="${HTTP_PROXY}" -e https_proxy="${HTTPS_PROXY}" -e no_proxy="${NO_PROXY}" "${CONTAINER_NAME}" bash -euxo pipefail -c '
  cd /work
  rm -rf litecoin-src
  git clone "'"${REPO_URL}"'" litecoin-src
  cd litecoin-src
  if [[ -n "'"${BRANCH_NAME}"'" ]]; then
    git checkout "'"${BRANCH_NAME}"'"
  fi
  ./autogen.sh
  CONFIG_SITE=/opt/litecoin/depends/x86_64-w64-mingw32/share/config.site ./configure --prefix=/ --host=x86_64-w64-mingw32
  make -j"$(nproc)"

  mkdir -p /work/output
  cp -v src/acecnd.exe /work/output/
  cp -v src/acec-cli.exe /work/output/
  cp -v src/acec-tx.exe /work/output/
  cp -v src/qt/acec-qt.exe /work/output/
'

echo "Build complete. Artifacts are in ${WORK_DIR}/output"
