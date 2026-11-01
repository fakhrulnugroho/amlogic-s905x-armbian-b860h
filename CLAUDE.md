# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A fork of `ophub/amlogic-s9xxx-armbian` limited to the ZTE B860H (Amlogic S905X, 2 GB RAM, board `s905x-b860h`). Bash tooling and overlay files repackage a generic Armbian image into an image for this box, and a separate pipeline compiles kernels. Rockchip, Allwinner and other Amlogic support has been removed, and `B860H-FORK-JOURNEY.md` tracks the plan. Armbian itself is not built here: CI gets the base image from `armbian/build`, and `rebuild` swaps in the kernel, bootloader and device files.

## Commands

There is no test suite, lint config or package manifest, and no workflow runs on push or PR.

```bash
# Syntax-check an edited script. This is the only check that is safe to run anywhere.
bash -n rebuild

# Install host dependencies (ubuntu2204- and ubuntu2604- variants also exist)
sudo apt-get install -y $(cat compile-kernel/tools/script/ubuntu2404-build-armbian-depends)

# Repackage one board: the smallest real end-to-end test
sudo ./rebuild -b s905x-b860h -k 6.12.y

# Use an exact kernel, skipping the latest-version lookup (-a false requires -k)
sudo ./rebuild -b s905x-b860h -k 6.12.114 -a false

# Compile a kernel, or only its DTBs
sudo ./recompile -k 6.12.y
sudo ./recompile -k 6.12.y -m dtbs
```

`rebuild` has no dry run. It needs root, loop devices and mounts, and it derives every path from `$PWD`, so run it from the repo root. Flags are documented in `README.md` (`rebuild`) and `compile-kernel/README.md` (`recompile`).

Local `rebuild` input must be an uncompressed image matching `build/output/images/*-trunk_*.img` with an ext4 rootfs. The version in the filename sets the output name. `action.yml` decompresses and renames images for CI; local runs do not. Output is `build/output/images/Armbian_<ver>_<platform>_<board>_<codename>_<kernel>_server_<date>.img.gz`.

`rebuild` downloads missing kernels and u-boot at runtime from `ophub/kernel` and `ophub/u-boot` into gitignored directories. It no longer downloads `ophub/firmware`, and `refactor_rootfs` deletes every entry in the image's `usr/lib/firmware` except `meson`, `rtl_nic` and `regulatory.db*`. It also masks the WiFi, NFS, OpenVPN, `vnstat` and `man-db` units, so a service that must run needs removing from that list.

## Architecture

### Image pipeline (`rebuild`)

Setup runs once: `init_var` → `check_data` (resolves `-b` to boards and kernel tags) → `find_armbian` → `download_depends` → `query_kernel` → `download_kernel`.

`loop_rebuild` then runs `confirm_version` per board, followed by these steps per board and kernel: `extract_armbian` → `make_image` → `copy_files` → `replace_kernel` → `refactor_bootfs` → `refactor_rootfs` → `clean_tmp`.

Images use msdos partitioning with a fat32 boot partition (`make_image`). `PLATFORM` is always `amlogic`, and it stays as data because kernel file names, `/boot/dtb/amlogic` and `/etc/ophub-release` depend on it.

### Device database

`build-armbian/armbian-files/common-files/etc/model_database.conf` is the source of truth: colon-separated rows with 15 columns, documented in its header. It is read at build time by `rebuild`, and on the device by `armbian-install` and `armbian-fix`.

- `BOARD` (column 14) is the `-b` value and the `different-files/<board>` directory name. Only rows 105 (`s905x`, a P212 DTB fallback) and 106 (`s905x-b860h`) remain. `BUILD` (column 15) controls inclusion in `all`, platform and range selections. An explicit `-b <board>` ignores it.
- `KERNEL_TAGS` (column 9) is `<tag>/<versions>`. `<tag>` maps to the `kernel_<tag>` release in the kernel repo and, for `<tag>/all`, to the `<tag>_kernel` array at the top of `rebuild`.
- `clean_model_conf` removes every space and every literal `NA` or `NULL`, including inside values. Keep those strings out of fields the scripts act on, such as `BOARD` and `FDTFILE`.
- `amlogic_uboot` at the top of `rebuild` lists the overload files, and every entry must exist in `ophub/u-boot`. A row that uses another `UBOOT_OVERLOAD` needs its file added there.

### Overlay files

`copy_files` layers `build-armbian/armbian-files/` in this order, with later layers overriding earlier ones:

1. `common-files/` (mapped to `/`)
2. `platform-files/amlogic/{bootfs,rootfs}`
3. `different-files/<board>/{bootfs,rootfs}` (no board has one yet, and `rebuild` skips it when missing)

`bootfs` maps to `/boot` and `rootfs` to `/`. Rootfs copies keep file modes, so the executable bit in git matters.

`refactor_bootfs` fills in `uEnv.txt` and `extlinux/extlinux.conf.bak` with `sed`. Boot templates must keep the placeholders it matches: `LABEL=ROOTFS` and a `meson*.dtb` name.

`different-files/<board>/rootfs/etc/armbian-board-release.conf` is an optional hook sourced as root inside `make_image`. It can set `skip_mb`, and can define `write_board_bootloader` (with `write_board_file="yes"`) and `adjust_kernel_files_cmd` (with `adjust_kernel_files="yes"`). These run in `rebuild`'s scope and use its variables, so renaming those variables can break the hooks.

### Kernel pipeline (`recompile`)

`recompile` is a host wrapper. It starts the privileged `armbian-ophub` container from `ophub/armbian-resolute:arm64` (with QEMU on non-aarch64 hosts) and runs `armbian-kernel -u`, then `armbian-kernel <args>`. That calls `compile-kernel/tools/script/armbian_compile_kernel.sh`, which refuses to run outside aarch64.

**Local edits under `compile-kernel/` do not survive `./recompile`.** `armbian-kernel -u` pulls `compile-kernel/` from this fork's `main` on GitHub and copies it into `/opt/kernel/compile-kernel`, which is bind-mounted from the host directory. Changes to that script only take effect once they are pushed to `main`.

- Config: `compile-kernel/tools/config/config-<major.minor>` if present, otherwise downloaded from `ophub/kernel` (`kernel-config/release/<flavor>`).
- Patches, applied with `-p true`: `compile-kernel/tools/patch/common-kernel-patches/` and `compile-kernel/tools/patch/<source-repo-name>/`.
- Output: `boot-`, `dtb-<platform>-`, `modules-` and `header-*.tar.gz` plus debs in `compile-kernel/output/`.

To use a local kernel in `rebuild`, put those four tarballs in `build-armbian/kernel/<tag>/<x.y.z>/`.

### GitHub Action and workflows

`action.yml` is a composite action with `build_target: armbian | kernel`. It normalises the input image and maps inputs to `rebuild` or `recompile` flags, so a new flag usually also needs a new input and a docs update.

Workflows are manual (`workflow_dispatch` or `repository_dispatch`) and call `fakhrulnugroho/amlogic-s905x-armbian-b860h@main`, so they run this fork's `main` on GitHub, not the local checkout or a branch. Changes to `rebuild` can only be tested by CI after they are pushed to `main`. CI installs host packages from `https://ophub.org/ubuntu*-build-armbian-depends`, not the local copies.

- `build-armbian-arm64-server-image.yml`: builds a base image with `armbian/build`, then repackages it.
- `build-armbian-using-releases-files.yml`: repackages the latest `-trunk_` image from this fork's Releases, so the base image stays the same.
- Docker image workflows use `compile-kernel/tools/script/docker/`.

### Device-side scripts

`common-files/usr/sbin/armbian-*` and `platform-files/amlogic/rootfs/usr/sbin/armbian-install` run on target devices, not the build host. `armbian-sync` pulls these scripts straight from this fork's `main`, so a merged change reaches deployed devices without a new image.

`armbian-install` always uses the s905x layout (`BLANK1=700`, `BOOT=512`, `BLANK2=0`). It no longer runs ampart and has no `-a` option, because that was the only path to the 117 MiB layout. The `/usr/bin/ampart` binary stays for eMMC diagnostics.

## Conventions

- **Adding a device:** add a row to `model_database.conf` with a unique `BOARD`, add `different-files/<board>/` if needed, and add the board to the `armbian_board` options in the two build workflows above, whose lists are identical. U-boot files live in the `ophub/u-boot` repo, not here. See section 12.15 of `documents/README.md`.
- **Scripts:** bash with no top-level `set -e`, so check failures explicitly with `|| error_msg "..."`. Each main script has a "Functions list" header to keep in sync.
- **Docs:** READMEs are English only, in the root, `build-armbian/`, `compile-kernel/` and `documents/`. Much of `documents/README.md` still describes upstream devices.
- **Docs vs code:** trust the scripts and `action.yml` for defaults. The docs have drifted: `rebuild` defaults to a 3000 MiB rootfs (docs say 2560), and `action.yml` defaults to kernels `6.1.y_6.12.y` and the `clang` toolchain (docs say `6.12.y_6.18.y` and `gcc`).
