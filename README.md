# openresty-ppc64le

**Unofficial, build-focused ppc64le (IBM Power) OpenResty binaries and Docker images. Caveat emptor.**

This is not an OpenResty release channel. It exists so the Power community can test OpenResty on ppc64le while the LuaJIT PPC64 fix is reviewed upstream:

- Issue: https://github.com/openresty/openresty/issues/1152
- Fix (draft, LLM-assisted, unreviewed): https://github.com/openresty/luajit2/pull/279

OpenResty 1.31.1.1 on ppc64le returns `0LL` from `ffi.cast("int64_t", n)`, which silently breaks `ngx.re`. These builds replace the bundled LuaJIT with a patched luajit2 ref.

## What you get

- Image: `ghcr.io/neomantra/openresty-ppc64le:<tag>`
- Testing image: `ghcr.io/neomantra/openresty-ppc64le:testing` is the latest `main` build (also `:sha-<short>`). It is unreleased, and emulated unless the run was native.
- Tarball: the `/usr/local/openresty` install tree, attached to each release
- LuaJIT runs interpreter-only (no JIT, FFI kept); PCRE JIT is on
- Base: UBI 9

## Validation status

Releases say whether they were built **emulated** (QEMU) or **native**. Only native runs count as validated. CI builds and smoke-tests on native POWER9 runners (IBM [actionspz](https://github.com/IBM/actionspz), `ubuntu-24.04-ppc64le`).

CI also builds and smoke-tests natively on s390x (`ubuntu-24.04-s390x`) as a validation check only: the patched LuaJIT is a ppc64le fix, and no s390x image or tarball is published.

## Build and test locally

```sh
docker buildx build --platform linux/ppc64le --load --target runtime -t openresty-ppc64le:dev .
docker run --rm --platform linux/ppc64le openresty-ppc64le:dev smoke.sh
```

Build args: `OPENRESTY_VERSION`, `LUAJIT_REPO`, `LUAJIT_REF`. Once the fix is upstream, point `LUAJIT_REPO`/`LUAJIT_REF` at luajit2 master.

## Reporting results

On real POWER hardware, run `docker run --rm ghcr.io/neomantra/openresty-ppc64le:<tag> smoke.sh` and comment on issue #1152 with `uname -m`, your distro, `gcc --version`, and the smoke output. Paste the full output if anything fails.

## Maintainers

- New GHCR packages start private. After the first tag push, make `openresty-ppc64le` public (Package settings -> Change visibility) or the pull command above will be denied for everyone else.
- The OpenResty source tarball is pinned by SHA-256 (`OPENRESTY_SHA256` in the Dockerfile, trust on first use). Update it together with `OPENRESTY_VERSION`.
- Release workflow runs refuse a `luajit_ref` override, so every release is built from the Dockerfile's default ref.

## Copyright & License

`openresty-ppc64le` is licensed under the 2-clause BSD license, like OpenResty. See [LICENSE](LICENSE).

Copyright (c) 2026, Evan Wies evan@neomantra.net.
