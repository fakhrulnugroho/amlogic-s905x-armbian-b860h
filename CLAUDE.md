# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Bash tooling and overlay files that repackage a generic Armbian image into per-device images for Amlogic, Rockchip and Allwinner boxes and SBCs, plus a separate kernel compile pipeline. Armbian itself is not built here: CI gets the base image from `armbian/build`, and `rebuild` swaps in the kernel, bootloader and device files.

## Commands

There is no test suite, lint config or package manifest, and no workflow runs on push or PR.

```bash
# Syntax-check an edited script. This is the only check that is safe to run anywhere.
bash -n rebuild

# Install host dependencies (ubuntu2204- and ubuntu2604- variants also exist)
sudo apt-get install -y $(cat compile-kernel/tools/script/ubuntu2404-build-armbian-depends)

# Repackage one board: the smallest real end-to-end test
sudo ./rebuild -b s905x3 -k 6.12.y

# Use an exact kernel, skipping the latest-version lookup (-a false requires -k)
sudo ./rebuild -b s905x3 -k 6.12.69 -a false

# Compile a kernel, or only its DTBs
sudo ./recompile -k 6.12.y
sudo ./recompile -k 6.12.y -m dtbs
```

`rebuild` has no dry run. It needs root, loop devices and mounts, and it derives every path from `$PWD`, so run it from the repo root. Flags are documented in `README.md` (`rebuild`) and `compile-kernel/README.md` (`recompile`).

Local `rebuild` input must be an uncompressed image matching `build/output/images/*-trunk_*.img` with an ext4 rootfs. The version in the filename sets the output name. `action.yml` decompresses and renames images for CI; local runs do not. Output is `build/output/images/Armbian_<ver>_<platform>_<board>_<codename>_<kernel>_server_<date>.img.gz`.

`rebuild` downloads missing kernels, u-boot and firmware at runtime from `ophub/kernel`, `ophub/u-boot` and `ophub/firmware`. Kernels and u-boot land in gitignored directories, but firmware lands in `build-armbian/armbian-files/common-files/usr/lib/firmware`, which is not ignored, so never stage it.

## Architecture

### Image pipeline (`rebuild`)

Setup runs once: `init_var` → `check_data` (resolves `-b` to boards and kernel tags) → `find_armbian` → `download_depends` → `query_kernel` → `download_kernel`.

`loop_rebuild` then runs `confirm_version` per board, followed by these steps per board and kernel: `extract_armbian` → `make_image` → `copy_files` → `replace_kernel` → `refactor_bootfs` → `refactor_rootfs` → `clean_tmp`.

Partition layout depends on the platform (`make_image`): Amlogic uses msdos with fat32 boot, Rockchip uses gpt with ext4 boot, and Allwinner uses msdos with fat32 boot. Each platform also writes its bootloader differently.

### Device database

`build-armbian/armbian-files/common-files/etc/model_database.conf` is the source of truth: colon-separated rows with 15 columns, documented in its header. It is read at build time by `rebuild`, and on the device by `armbian-install` and `armbian-fix`.

- `BOARD` (column 14) is the `-b` value and the `different-files/<board>` directory name. `BUILD` (column 15) controls inclusion in `all`, platform and range selections. An explicit `-b <board>` ignores it.
- `KERNEL_TAGS` (column 9) is `<tag>/<versions>`. `<tag>` maps to the `kernel_<tag>` release in the kernel repo and, for `<tag>/all`, to the `<tag>_kernel` array at the top of `rebuild`.
- `clean_model_conf` removes every space and every literal `NA` or `NULL`, including inside values: `FriendlyElec-CM3588-NAS` is read as `FriendlyElec-CM3588-S`. Keep those strings out of fields the scripts act on, such as `BOARD` and `FDTFILE`.
- IDs on `[IDL]` rows are hard-coded in `armbian-install`. Do not change them.

### Overlay files

`copy_files` layers `build-armbian/armbian-files/` in this order, with later layers overriding earlier ones:

1. `common-files/` (mapped to `/`)
2. `platform-files/<platform>/{bootfs,rootfs}`
3. `different-files/<board>/{bootfs,rootfs}`

`bootfs` maps to `/boot` and `rootfs` to `/`. Rootfs copies keep file modes, so the executable bit in git matters.

`refactor_bootfs` fills in `uEnv.txt`, `extlinux/extlinux.conf.bak` and `armbianEnv.txt` with `sed`. Boot templates must keep the placeholders it matches: `LABEL=ROOTFS` and `meson*.dtb`, `sun*.dtb` or `rk*.dtb` names.

`different-files/<board>/rootfs/etc/armbian-board-release.conf` is an optional hook sourced as root inside `make_image`. It can set `skip_mb`, and can define `write_board_bootloader` (with `write_board_file="yes"`) and `adjust_kernel_files_cmd` (with `adjust_kernel_files="yes"`). These run in `rebuild`'s scope and use its variables, so renaming those variables can break the hooks. See `a311d-oes`, `s922x-oes-plus`, `wxy-oect` and `torder-r10d`.

### Kernel pipeline (`recompile`)

`recompile` is a host wrapper. It starts the privileged `armbian-ophub` container from `ophub/armbian-resolute:arm64` (with QEMU on non-aarch64 hosts) and runs `armbian-kernel -u`, then `armbian-kernel <args>`. That calls `compile-kernel/tools/script/armbian_compile_kernel.sh`, which refuses to run outside aarch64.

**Local edits under `compile-kernel/` do not survive `./recompile`.** `armbian-kernel -u` pulls `compile-kernel/` from `ophub/amlogic-s9xxx-armbian` `main` and copies it into `/opt/kernel/compile-kernel`, which is bind-mounted from the host directory. Changes to that script only take effect once they are on upstream `main`.

- Config: `compile-kernel/tools/config/config-<major.minor>` if present, otherwise downloaded from `ophub/kernel` (`kernel-config/release/<flavor>`).
- Patches, applied with `-p true`: `compile-kernel/tools/patch/common-kernel-patches/` and `compile-kernel/tools/patch/<source-repo-name>/`.
- Output: `boot-`, `dtb-<platform>-`, `modules-` and `header-*.tar.gz` plus debs in `compile-kernel/output/`.

To use a local kernel in `rebuild`, put those four tarballs in `build-armbian/kernel/<tag>/<x.y.z>/`.

### GitHub Action and workflows

`action.yml` is a composite action with `build_target: armbian | kernel`. It normalises the input image and maps inputs to `rebuild` or `recompile` flags, so a new flag usually also needs a new input and a docs update.

Workflows are manual (`workflow_dispatch` or `repository_dispatch`) and call `ophub/amlogic-s9xxx-armbian@main`, so they run upstream `main`, not the local checkout. Forks must repoint `uses:`. CI installs host packages from `https://ophub.org/ubuntu*-build-armbian-depends`, not the local copies.

- `build-armbian-arm64-server-image.yml`: builds a base image with `armbian/build`, then repackages it.
- `build-armbian-using-releases-files.yml`: repackages an image from Releases.
- `build-armbian-using-official-image.yml`: repackages an official Armbian image.
- Docker image workflows use `compile-kernel/tools/script/docker/`.

### Device-side scripts

`common-files/usr/sbin/armbian-*` and `platform-files/{amlogic,allwinner}/rootfs/usr/sbin/armbian-install` run on target devices, not the build host. Rockchip has no `armbian-install`. `armbian-sync` pulls these scripts straight from upstream `main`, so a merged change reaches deployed devices without a new image.

## Conventions

- **Adding a device:** add a row to `model_database.conf` with a unique `BOARD`, add `different-files/<board>/` if needed, and add the board to the `armbian_board` options in the three workflows above, whose lists are identical. U-boot files live in the `ophub/u-boot` repo, not here. See section 12.15 of `documents/README.md`.
- **Scripts:** bash with no top-level `set -e`, so check failures explicitly with `|| error_msg "..."`. Each main script has a "Functions list" header to keep in sync.
- **Docs:** each README exists as `.md`, `.cn.md` and `.ja.md` in the root, `build-armbian/`, `compile-kernel/` and `documents/`. Keep all three in step for user-facing changes.
- **Docs vs code:** trust the scripts and `action.yml` for defaults. The docs have drifted: `rebuild` defaults to a 3000 MiB rootfs (docs say 2560), and `action.yml` defaults to kernels `6.1.y_6.12.y` and the `clang` toolchain (docs say `6.12.y_6.18.y` and `gcc`).
