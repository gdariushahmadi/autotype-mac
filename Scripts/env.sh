#!/usr/bin/env bash
# Keeps every build artefact inside the workspace so the build works under a
# file sandbox that denies writes to ~/Library and the shared temp directory.
export AUTOTYPE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${AUTOTYPE_ROOT}/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${AUTOTYPE_ROOT}/.build/ModuleCache"
export SWIFTPM_DISABLE_SANDBOX=1
mkdir -p "${CLANG_MODULE_CACHE_PATH}"
