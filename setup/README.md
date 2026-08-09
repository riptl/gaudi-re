# Intel Gaudi 1.24.1 on Fedora 44

This repository records the compatibility changes used to install Intel Gaudi
software `1.24.1-482.el9` from the RHEL 9.8 mirror on Fedora 44.

## Scope

The driver patch was validated on Fedora kernel `6.19.10-300.fc44.x86_64` with
GCC 16. It:

- detects `u64_to_user_ptr` in its Linux 6.19 header location;
- keeps one GCC 16 unused-variable diagnostic from aborting the kernel build;
- initializes three error returns that GCC 16 correctly identifies as possibly
  uninitialized.

The thunk patch keeps GCC 16's `maybe-uninitialized` diagnostic as a warning
while retaining the project's other `-Werror` checks.

Kernel `7.1.3-201.fc44.x86_64` is **not supported** by these patches because it
removes the `dma_buf_attach_ops.move_notify` member used by this driver.

## Files

- `habanalabs-rhel98.repo`: Habana RHEL 9.8 package repository.
- `habanalabs-cmake3-compat.spec`: provides the legacy `cmake3` RPM capability
  using Fedora's `cmake` package.
- `patches/habanalabs-driver-fedora44.patch`: proven DKMS compatibility changes.
- `patches/habanalabs-thunk-fedora44.patch`: proven thunk GCC 16 change.
- `apply-patches.sh`: applies both patches and rebuilds the driver and thunk.

## Installation

These commands assume this repository is the current directory and the machine
is running Fedora 44 on a supported Linux 6.19 kernel:

```bash
source /etc/os-release
test "$ID" = fedora
test "$VERSION_ID" = 44
case "$(uname -r)" in 6.19.*.fc44.*) ;; *) echo "Unsupported kernel"; exit 1;; esac
```

### 1. Configure the Habana mirror and signing keys

Install the included repository definition:

```bash
sudo install -m 0644 habanalabs-rhel98.repo \
  /etc/yum.repos.d/habanalabs_synapseai.repo
```

Import both Habana signing keys. The first signs repository metadata and the
second signs the package payloads:

```bash
curl -fsSL \
  https://vault.habana.ai/artifactory/api/v2/repositories/rhel/keyPairs/primary/public \
  | sudo rpm --import -
curl -fsSL \
  https://vault.habana.ai/artifactory/gaudi-general/keyPairs/primary/public \
  | sudo rpm --import -
sudo dnf makecache --repo=habanalabs_synapseai_1.24.1
```

### 2. Install Fedora build dependencies

```bash
sudo dnf install -y \
  sudo dnf-utils which gcc gcc-c++ cmake make ninja-build lsof curl wget file jq \
  dkms "kernel-devel-$(uname -r)" kernel-headers \
  libfdt-devel libnl3-devel systemd-devel boost-devel valgrind-devel \
  libcurl-devel openssl-devel python3 rpm-build
```

Installing `kernel-devel` may also pull a newer Fedora kernel. Do not boot that
kernel unless the Habana DKMS build has been validated for it. These patches do
not support kernel 7.1.

### 3. Install the `cmake3` RPM capability shim

The RHEL RPMs require both `cmake` and the legacy RPM capability `cmake3`.
Fedora only provides the former, so build and install the included empty shim:

```bash
rpmbuild -bb \
  --define "_topdir $PWD/.rpmbuild" \
  habanalabs-cmake3-compat.spec
sudo dnf install -y \
  "$PWD/.rpmbuild/RPMS/noarch/habanalabs-cmake3-compat-1-1.fc44.noarch.rpm"
```

### 4. Install firmware and the driver sources

```bash
sudo dnf install -y \
  habanalabs-firmware-1.24.1-482.el9 \
  habanalabs-1.24.1-482.el9
```

On an unpatched Fedora 44 system, the driver RPM's post-install DKMS build is
expected to fail. The RPM files should nevertheless be installed. Confirm that
the source and firmware are present before continuing:

```bash
rpm -q habanalabs habanalabs-firmware
test -d /usr/src/habanalabs-1.24.1-482
test -f /lib/firmware/habanalabs/gaudi2/gaudi2-boot-fit.itb
```

### 5. Install the user-space stack

```bash
sudo dnf install -y \
  habanalabs-rdma-core-1.24.1-482.el9 \
  habanalabs-thunk-1.24.1-482.el9 \
  habanalabs-graph-1.24.1-482.el9 \
  habanalabs-firmware-tools-1.24.1-482.el9 \
  habanalabs-firmware-odm-1.24.1-482.el9 \
  habanalabs-qual-1.24.1-482.el9
```

The thunk RPM's post-install source build is expected to fail under GCC 16
before its patch is applied. As with the driver, verify that the RPM and source
tree were installed:

```bash
rpm -q habanalabs-rdma-core habanalabs-thunk habanalabs-graph \
  habanalabs-firmware-tools habanalabs-firmware-odm habanalabs-qual
test -d /opt/habanalabs/src/hl-thunk
```

### 6. Apply the compatibility patches and rebuild

```bash
chmod +x apply-patches.sh
./apply-patches.sh
```

The helper refuses kernels outside the tested Fedora 44 Linux 6.19 series. It
patches the installed source trees, builds and installs the DKMS modules for the
running kernel, rebuilds the thunk libraries, and runs `ldconfig`.

If Fedora installed a newer unsupported kernel, retain 6.19 as the boot default:

```bash
sudo grubby --set-default "/boot/vmlinuz-$(uname -r)"
```

### 7. Reload the driver

First ensure no process is using the accelerator:

```bash
sudo fuser -v /dev/accel/accel0 /dev/accel/accel_controlD0
```

When the command reports no users, reload the modules in dependency order:

```bash
sudo modprobe -r \
  habanalabs_ib habanalabs_en habanalabs_cn habanalabs habanalabs_compat
sudo modprobe habanalabs_compat
sudo modprobe habanalabs
sudo modprobe habanalabs_cn
sudo modprobe habanalabs_en
sudo modprobe habanalabs_ib
```

### 8. Validate the installation

```bash
modinfo -F filename habanalabs
modinfo -F version habanalabs
dkms status
ldd /usr/lib/habanalabs/libhl-thunk.so | grep 'not found' && exit 1 || true
ldd /usr/lib/habanalabs/libSynapse.so | grep 'not found' && exit 1 || true
hl-smi
sudo dnf check
```

For the tested installation, `modinfo` resolves to the module under
`/lib/modules/$(uname -r)/extra/`, reports version `1.24.1-b336d5e`, and
`hl-smi` detects the Gaudi2 accelerator.

The repository disables `repo_gpgcheck` because DNF 5 did not retain the remote
metadata key. The metadata signature was manually verified against Habana's
published primary key; individual RPM signature checking remains enabled.
