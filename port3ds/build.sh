#!/usr/bin/env bash
# Build needy3ds.3dsx with devkitPro installed inside MSYS2.
export DEVKITPRO=/opt/devkitpro DEVKITARM=/opt/devkitpro/devkitARM
export PATH=/opt/devkitpro/tools/bin:/opt/devkitpro/devkitARM/bin:$PATH
cd "$(dirname "$0")" && make -j8 "$@"
