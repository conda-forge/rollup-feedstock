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

# ensure Rust wasm32 sysroot is actually installed (not just listed by rustc)
if [ ! -d "${BUILD_PREFIX}/lib/rustlib/wasm32-unknown-unknown" ]; then
    echo "wasm32-unknown-unknown sysroot not found in BUILD_PREFIX — add rust-std-wasm32-unknown-unknown to build requirements"
    exit 1
fi

# remove stale upstream patch-package patches that no longer match dependencies
rm -f patches/@types+rimraf+*.patch
rm -f patches/@vueuse+core+*.patch

pnpm import
pnpm install --ignore-scripts

# allow stable rustc to accept nightly -Z flags
# (rollup's rust/bindings_wasm/.cargo/config.toml uses -Z location-detail=none + -Z build-std)
export RUSTC_BOOTSTRAP=1

# Patch rollup's nightly-only build config for Rust 1.96 compatibility:
# `panic_immediate_abort` cfg form was rejected in Rust 1.96 (now a real panic strategy
# enabled via `panic = "immediate-abort"` in Cargo.toml). `optimize_for_size` still works.
cat > rust/bindings_wasm/.cargo/config.toml <<'EOF'
[build]
rustflags = "-C opt-level=z -Z location-detail=none"

[unstable]
build-std = ["std", "core", "alloc", "panic_abort"]
build-std-features = ["optimize_for_size"]
EOF

# Override conda's $CARGO_HOME/config.toml rustflags (contains -C link-arg=-Wl,-rpath
# which rust-lld rejects for wasm32). Setting RUSTFLAGS env replaces ALL config-derived
# rustflags per cargo's precedence rules, suppressing the rpath leak.
export RUSTFLAGS="-C opt-level=z -Z location-detail=none"

# Bootstrap rollup (from $BUILD_PREFIX) resolves plugin packages relative to its own
# install path. Add source tree's node_modules to NODE_PATH so typescript plugin
# (and other build:js deps) resolve correctly.
export NODE_PATH="$SRC_DIR/node_modules"

# TypeScript compiler doesn't honor NODE_PATH — make rollup's type declarations
# visible to tsc by symlinking the conda rollup package into the source node_modules.
ln -sfn "$BUILD_PREFIX/lib/node_modules/rollup" "$SRC_DIR/node_modules/rollup"

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
