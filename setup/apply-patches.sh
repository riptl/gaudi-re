#!/usr/bin/env bash
set -euo pipefail

release="1.24.1-482"
kernel="${1:-$(uname -r)}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
driver_src="/usr/src/habanalabs-${release}"
thunk_src="/opt/habanalabs/src/hl-thunk"

if [[ ! -d "$driver_src" || ! -d "$thunk_src" ]]; then
    echo "Install habanalabs and habanalabs-thunk ${release} before applying patches." >&2
    exit 1
fi

if [[ "$kernel" != 6.19.*.fc44.* ]]; then
    echo "Refusing unvalidated kernel $kernel; this kit was tested on Fedora 44 kernel 6.19." >&2
    exit 1
fi

sudo patch --directory="$driver_src" --strip=1 --forward \
    --input="$root_dir/patches/habanalabs-driver-fedora44.patch"
sudo dkms build --force --module=habanalabs --module-version="$release" --kernelver="$kernel"
sudo dkms install --force --module=habanalabs --module-version="$release" --kernelver="$kernel"

sudo patch --directory="$thunk_src" --strip=1 --forward \
    --input="$root_dir/patches/habanalabs-thunk-fedora44.patch"

source /etc/profile.d/habanalabs-rdma-core.sh
sudo env \
    PATH="$PATH" \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" \
    RDMA_CORE_ROOT="$RDMA_CORE_ROOT" \
    RDMA_CORE_LIB="$RDMA_CORE_LIB" \
    EXTRA_CMAKE_FLAGS="-DHLTESTS_LIB_MODE=ON -DHLTESTS_IB=ON" \
    "$thunk_src/build.sh"

sudo install -o root -g root -m 0755 \
    "$thunk_src/build/lib/libhl-thunk.so" \
    "$thunk_src/build/lib/libhl-thunk-err_injection.so" \
    "$thunk_src/build/lib/libhl-thunk-tests.so" \
    /usr/lib/habanalabs/
sudo ldconfig

echo "Patched driver and thunk for kernel $kernel."
