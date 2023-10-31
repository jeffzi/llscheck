FROM akorn/luarocks:lua5.4-alpine

SHELL ["/bin/ash", "-o", "pipefail", "-c"]

ARG LLS_VERSION

WORKDIR /opt
RUN mkdir luals
ENV PATH="${PATH}:/opt/luals/bin"

RUN apk update && apk upgrade
RUN apk add --no-cache gcc git musl-dev wget

RUN LATEST_VERSION=$(git ls-remote --refs --sort="version:refname" --tags  https://github.com/LuaLS/lua-language-server | cut -d/ -f3-|tail -n1) \
    && VERSION=$(if [ -z "$LLS_VERSION" ] ;then echo "$LATEST_VERSION" ; else echo "$LLS_VERSION" ; fi) \
    && ARCHIVE="lua-language-server-$VERSION-linux-x64-musl.tar.gz" \
    && wget -q https://github.com/LuaLS/lua-language-server/releases/download/"$VERSION"/"$ARCHIVE" \
    && tar zxf "$ARCHIVE" --directory=luals

RUN luarocks install llscheck

WORKDIR /data

ENTRYPOINT ["llscheck"]
