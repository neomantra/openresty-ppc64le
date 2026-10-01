# openresty-ppc64le: Design

Date: 2026-10-01
Repo: `github.com/neomantra/openresty-ppc64le` (new, separate from `docker-openresty`)
Image: `ghcr.io/neomantra/openresty-ppc64le`

## Purpose

Give the IBM/Power community a testable, build-focused source of **ppc64le OpenResty binaries and Docker images** while the LuaJIT PPC64 fix (openresty/luajit2 PR #279) is reviewed and merged upstream. Context: openresty/openresty issue #1152. OpenResty 1.31.1.1 on ppc64le returns `0LL` from `ffi.cast("int64_t", n)`, which silently breaks `ngx.re`. The fix is in `src/vm_ppc.dasc`.

This is **unofficial**. It carries a `caveat emptor` notice, like the build-from-source flavors in `docker-openresty`. It is not an OpenResty release channel.

## Scope

In:
- ppc64le only, one RHEL-compatible distro (UBI 9).
- OpenResty 1.31.1.1 with the bundled LuaJIT replaced by a pinned luajit2 ref containing the PPC64 fix.
- Outputs: an install-tree tarball and a runtime Docker image.
- Smoke tests that guard the regression.
- GitHub Actions CI using QEMU emulation, with a `runs-on` input so native POWER runners can be swapped in later.

Out (YAGNI for the first cut): other distros (Debian, Alpine), s390x or other arches, RPM packaging, multi-version matrices, JIT-enabled LuaJIT.

## Success criteria

1. A CI run on `linux/ppc64le` produces a tarball and an image, and all smoke tests pass.
2. The same smoke tests fail against an unpatched build (the regression is demonstrated, not assumed).
3. Dropping the patch later is a one-line change (the `LUAJIT_REF` build arg).
4. Runs are labeled `emulated` or `native`. Only native runs are described as validated.

## Architecture

Dockerfile-first, a single source of truth shared by local dev and CI.

```
Dockerfile            multi-stage: build -> export (tarball) -> runtime
scripts/smoke.sh      smoke tests, run inside the built image
.github/workflows/build.yml
README.md             caveat emptor, upstream issue link, how to report results
```

### Dockerfile stages

- `build` (ubi9): installs gcc, make, git, perl, pcre2, openssl-devel, zlib-devel. Downloads `openresty-${OPENRESTY_VERSION}.tar.gz`. Removes `bundle/LuaJIT-*` and clones luajit2 at `LUAJIT_REF` into the same directory name. `git` stays on PATH, because LuaJIT derives its version stamp from the git log. Runs `./configure` with `-DLUAJIT_DISABLE_JIT` (interpreter only, FFI kept) and PCRE JIT on, then `make` and `make install` into `/usr/local/openresty`.
- `export` (scratch): holds only the install tree, so `buildx --output type=local` can emit a tarball source.
- `runtime` (ubi9-minimal): copies the install tree, installs the runtime libs, sets `PATH`, a minimal `nginx.conf`, `CMD ["openresty","-g","daemon off;"]`.

Build args:
- `OPENRESTY_VERSION` (default `1.31.1.1`)
- `LUAJIT_REPO` (default `https://github.com/neomantra/openresty-luajit2.git`)
- `LUAJIT_REF` (default `d18fd8f681f644f83eee28bf63b1cf4b1be44cda`, the `ppc64le-num2int-fix` commit)

Setting `LUAJIT_REPO` to `https://github.com/openresty/luajit2.git` and `LUAJIT_REF` to a pre-fix tag reproduces the broken build. This is how criterion 2 is checked.

### Smoke tests (`scripts/smoke.sh`)

Run in the runtime image. Each must pass, and failure exits non-zero with the output:
- `ffi.cast` of `int64_t`, `uint64_t` and `intptr_t` for 123456789 equals the input (`123456789LL`, and `tonumber` returns 123456789).
- `ipairs` over `{1,2,10,100,255,256,1000,123456789,2147483647}` visits 9 elements.
- `resty -e` with `ngx.re.match("hello 12345 world", [[(\d+)]], "jo")` returns `12345`.
- `nginx -t` passes, and a minimal server answers a `curl` request.

### CI (`.github/workflows/build.yml`)

- Triggers: `workflow_dispatch` (inputs: `runs-on` default `ubuntu-latest`, `luajit_ref`) and `push` to main.
- Steps: set up QEMU and buildx, build `--platform linux/ppc64le`, run `scripts/smoke.sh` in the image, upload the tarball as an artifact.
- Release: on `v*` tags, push `ghcr.io/neomantra/openresty-ppc64le:<tag>` and attach the tarball. Release notes state `emulated` or `native` per run.
- A native job is a later change to `runs-on` only. No structural rework.

## Error handling

- The build fails fast if the luajit checkout lacks the expected PPC64 change (a `grep` for the 64-bit helpers in `vm_ppc.dasc`) when `LUAJIT_REF` is the default. This prevents silently shipping an unpatched build.
- The smoke script prints the exact failing command and output so reporters can paste it into issue #1152.

## Testing

- Smoke tests, as above, are the test suite.
- Negative control: build with the unpatched ref and confirm the smoke tests fail.
- Emulated runs are slow (expect an hour or more). CI timeouts are set accordingly.

## Risks and open items

- QEMU may mask or introduce differences. Mitigated by the `emulated` label and the native-runner hook. Native access (IBM actionspz, issue #118) is not yet available.
- The luajit2 PR is an unreviewed, LLM-assisted draft. The README says so plainly.
- The default ref is the draft-PR commit. Switch to luajit2 master once the PR merges.
