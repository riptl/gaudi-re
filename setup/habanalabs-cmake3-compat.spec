Name:           habanalabs-cmake3-compat
Version:        1
Release:        1%{?dist}
Summary:        RPM capability shim for Intel Gaudi RHEL packages on Fedora
License:        MIT
BuildArch:      noarch
Requires:       cmake
Provides:       cmake3

%description
Fedora provides CMake as cmake, while the RHEL Intel Gaudi packages also
require the legacy RPM capability cmake3. This package supplies only that
capability and installs no files.

%files

%changelog
* Sun Jul 19 2026 Codex <root@localhost> - 1-1
- Initial compatibility package
