Place optional offline bootstrap archives here.

Supported file names match the upstream download file names, for example:

- `ubuntu-base-24.04.3-base-arm64.tar.gz`
- `node-v24.14.1-linux-arm64.tar.xz`

If a matching file is bundled into the APK, setup will prefer that local copy
first and fall back to downloading it online if needed.

Prebuilt rootfs archives can also be placed here to skip runtime
`apt-get update/install` during first setup:

- `openclaw-rootfs-noble-arm64.tar.gz`
- `openclaw-rootfs-noble-armhf.tar.gz`
- `openclaw-rootfs-noble-amd64.tar.gz`

These archives should already include `ca-certificates git python3 make g++
curl wget`. If extraction or package detection fails, setup falls back to the
standard Ubuntu base rootfs flow.
