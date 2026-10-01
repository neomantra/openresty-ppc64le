ARG OPENRESTY_VERSION=1.31.1.1

FROM registry.access.redhat.com/ubi9 AS build
ARG OPENRESTY_VERSION
ARG LUAJIT_REPO=https://github.com/neomantra/openresty-luajit2.git
ARG LUAJIT_REF=d18fd8f681f644f83eee28bf63b1cf4b1be44cda
# Set to 0 only for the negative control (building an unpatched LuaJIT).
ARG REQUIRE_PPC64_FIX=1

# curl-minimal is preinstalled in UBI 9; installing full curl conflicts with it.
RUN dnf install -y gcc gcc-c++ make perl git tar gzip patch which \
        pcre2-devel openssl-devel zlib-devel \
    && dnf clean all
RUN command -v git >/dev/null || { echo "git is required during make" >&2; exit 1; }

WORKDIR /src
RUN curl -fsSL "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz" \
    | tar xz --strip-components=1

# Replace the bundled LuaJIT (directory name must match bundle/LuaJIT-[0-9]*).
RUN LJDIR="$(ls -d bundle/LuaJIT-[0-9]* | head -n1)" \
    && rm -rf "$LJDIR" \
    && git clone "$LUAJIT_REPO" "$LJDIR" \
    && git -C "$LJDIR" checkout "$LUAJIT_REF" \
    && if [ "$REQUIRE_PPC64_FIX" = "1" ]; then \
         grep -q fctidz "$LJDIR/src/vm_ppc.dasc" \
           || { echo "LUAJIT_REF lacks the PPC64 64-bit conversion fix (no fctidz in vm_ppc.dasc)" >&2; exit 1; }; \
       fi

RUN ./configure --prefix=/usr/local/openresty \
        --with-pcre-jit --with-http_ssl_module \
        --with-luajit-xcflags='-DLUAJIT_DISABLE_JIT' \
        -j"$(nproc)" \
    && make -j"$(nproc)" \
    && make install

FROM scratch AS export
COPY --from=build /usr/local/openresty /usr/local/openresty

FROM registry.access.redhat.com/ubi9-minimal AS runtime
# resty (the OpenResty CLI) is a Perl script.
RUN microdnf install -y pcre2 openssl-libs zlib curl-minimal perl-interpreter \
    && microdnf clean all
COPY --from=build /usr/local/openresty /usr/local/openresty
COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY scripts/smoke.sh /usr/local/bin/smoke.sh
ENV PATH=/usr/local/openresty/bin:/usr/local/openresty/luajit/bin:$PATH
EXPOSE 8080
CMD ["openresty", "-g", "daemon off;"]
