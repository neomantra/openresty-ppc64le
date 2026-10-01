# openresty-ppc64le

**Unofficial, build-focused ppc64le (IBM Power) OpenResty binaries and Docker images. Caveat emptor.**

This is not an OpenResty release channel. It exists so the Power community can test OpenResty on ppc64le while the LuaJIT PPC64 fix is reviewed upstream:

- Issue: https://github.com/openresty/openresty/issues/1152
- Fix (draft, LLM-assisted, unreviewed): https://github.com/openresty/luajit2/pull/279

OpenResty 1.31.1.1 on ppc64le returns `0LL` from `ffi.cast("int64_t", n)`, which silently breaks `ngx.re`. These builds replace the bundled LuaJIT with a patched luajit2 ref.

## What you get

- Image: `ghcr.io/neomantra/openresty-ppc64le:<tag>`
- Tarball: the `/usr/local/openresty` install tree, attached to each release
- LuaJIT runs interpreter-only (no JIT, FFI kept); PCRE JIT is on
- Base: UBI 9

## Validation status

Releases say whether they were built **emulated** (QEMU) or **native**. Only native runs count as validated. Native POWER runners are not yet available (IBM actionspz).

## Build and test locally

```sh
docker buildx build --platform linux/ppc64le --load --target runtime -t openresty-ppc64le:dev .
docker run --rm --platform linux/ppc64le openresty-ppc64le:dev smoke.sh
```

Build args: `OPENRESTY_VERSION`, `LUAJIT_REPO`, `LUAJIT_REF`. Once the fix is upstream, point `LUAJIT_REPO`/`LUAJIT_REF` at luajit2 master.

## Reporting results

On real POWER hardware, please run `smoke.sh` and comment on issue #1152 with `uname -m`, your distro, `gcc --version`, and the smoke output. Paste the full output if anything fails.
