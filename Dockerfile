FROM akorn/luarocks:lua5.4-alpine

ARG LLS_VERSION

WORKDIR /opt

RUN mkdir luals

ENV PATH="${PATH}:/opt/luals/bin"

RUN apk add --no-cache gcc git musl-dev wget

RUN LLS_ARCHIVE="lua-language-server-$LLS_VERSION-linux-x64-musl.tar.gz" \
    && wget -q https://github.com/LuaLS/lua-language-server/releases/download/$LLS_VERSION/$LLS_ARCHIVE \
    && tar zxf $LLS_ARCHIVE --directory=luals

RUN luarocks install llscheck

WORKDIR /data

ENTRYPOINT ["llscheck"]
