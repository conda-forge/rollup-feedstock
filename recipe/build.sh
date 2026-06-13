# #!/usr/bin/env bash
#
# Conda-forge recommended build
set -euxo pipefail

if [[ "${target_platform}" == "osx-arm64" || "${target_platform}" == "linux-aarch64" ]]; then
    export npm_config_arch="arm64"
fi

export npm_config_build_from_source=true

rm "${PREFIX}"/bin/node
ln -s "${BUILD_PREFIX}"/bin/node "${PREFIX}"/bin/node

export NPM_CONFIG_USERCONFIG=/tmp/nonexistentrc

# remove stale upstream patch-package patches that no longer match dependencies
rm -f patches/@types+rimraf+*.patch
rm -f patches/@vueuse+core+*.patch

pnpm import
pnpm install --ignore-scripts --config.bin-links=false
pnpm run build

pnpm pack
# Revert last .xx to -xx in PKG_VERSION
# _PKG_VERSION=$(echo "${PKG_VERSION}" | sed 's/\.\([^.]\+\)$/-\1/')
_PKG_VERSION=$(echo "${PKG_VERSION}")
npm install -g "${PKG_NAME}"-"${_PKG_VERSION}".tgz
pnpm licenses list --json | pnpm-licenses generate-disclaimer --json-input --output-file=ThirdPartyLicenses.txt

pushd rust
    cargo-bundle-licenses \
    --format yaml \
    --output ${SRC_DIR}/THIRDPARTY.yml
popd
