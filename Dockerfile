# We build our DevContainer on MS' Typescript-Node Devcontainer
# This gives us lots of standard stuff, and lets us layer a few custom things on top, like the Emscripten compiler, Puppeteer

# --------------------------------------------------------------------
# BEGIN Standard MS Devcontainer for Typescript-Node 

# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.155.1/containers/typescript-node/.devcontainer/base.Dockerfile
# [Choice] Node.js version: 14, 12, 10
ARG VARIANT="14-buster"
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:0-${VARIANT}

# [Optional] Uncomment if you want to install an additional version of node using nvm
# ARG EXTRA_NODE_VERSION=10
# RUN su node -c "source /usr/local/share/nvm/nvm.sh && nvm install ${EXTRA_NODE_VERSION}"

# [Optional] Uncomment if you want to install more global node packages
# RUN su node -c "npm install -g <your-package-list -here>"

# END Standard MS Devcontainer for Typescript-Node 
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# BEGIN EMSDK 
# Install EMSDK to /emsdk just like the EMSDK Dockerfile: https://github.com/emscripten-core/emsdk/blob/master/docker/Dockerfile
ENV EMSDK /emsdk
# We pin EMSDK to 2.0.15 rather than 'latest' so that everyone is using the same compiler version
ENV EMSCRIPTEN_VERSION 2.0.29

RUN git clone https://github.com/emscripten-core/emsdk.git $EMSDK

RUN echo "## Install Emscripten" \
    && cd ${EMSDK} \
    && ./emsdk install ${EMSCRIPTEN_VERSION} \
    && echo "## Done"

# Copied directly from https://github.com/emscripten-core/emsdk/blob/master/docker/Dockerfile
RUN cd ${EMSDK} \
    && echo "## Generate standard configuration" \
    && ./emsdk activate ${EMSCRIPTEN_VERSION} \
    && chmod 777 ${EMSDK}/upstream/emscripten \
    && chmod -R 777 ${EMSDK}/upstream/emscripten/cache \
    && echo "int main() { return 0; }" > hello.c \
    && ${EMSDK}/upstream/emscripten/emcc -c hello.c \
    && cat ${EMSDK}/upstream/emscripten/cache/sanity.txt \
    && echo "## Done"

ENV PATH $EMSDK:$EMSDK/upstream/emscripten/:$PATH

# Cleanup Emscripten installation and strip some symbols
# Copied directly from https://github.com/emscripten-core/emsdk/blob/master/docker/Dockerfile
RUN echo "## Aggressive optimization: Remove debug symbols" \
    && cd ${EMSDK} && . ./emsdk_env.sh \
    # Remove debugging symbols from embedded node (extra 7MB)
    && strip -s `which node` \
    # Tests consume ~80MB disc space
    && rm -fr ${EMSDK}/upstream/emscripten/tests \
    # Fastcomp is not supported
    && rm -fr ${EMSDK}/upstream/fastcomp \
    # strip out symbols from clang (~extra 50MB disc space)
    && find ${EMSDK}/upstream/bin -type f -exec strip -s {} + || true \
    && echo "## Done"

RUN echo ". /emsdk/emsdk_env.sh" >> /etc/bash.bashrc
# We must set the EM_NODE_JS environment variable for a somewhat silly reason
# We run our build scripts with `npm run`, which sets the NODE environment variable as it runs.
# The EMSDK picks up on that environment variable and gives a deprecation warning: warning: honoring legacy environment variable `NODE`.  Please switch to using `EM_NODE_JS` instead`
# So, we are going to put this environment variable here explicitly to avoid the deprecation warning.
RUN echo 'export EM_NODE_JS="$EMSDK_NODE"' >> /etc/bash.bashrc

# END EMSDK
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# BEGIN PUPPETEER dependencies
# Here we install all of the packages depended upon by Chrome (that Puppeteer will use for headless tests).
# We could also take a page from https://github.com/buildkite/docker-puppeteer/blob/master/Dockerfile instead,
# and install the latest stable version of Chrome to get the right dependencies, but that version changes over time,
# so the stable version of Chrome and the version installed by Puppeteer might diverge over time. 
# It also means they end up having Chrome downloaded and installed twice.
# We could install the particular version of Chrome that our version of Puppeteer would use and then tell Puppeteer not to download its own version of Chrome,
# but then we'd have to rebuild our Docker container every time we revved Puppeteer, and that feels fiddly too.
# For all of these reasons, it seems safer to simply install the explicit list packages depended upon by Chrome, assume that's unlikely to change
# and move on.

# List taken from:
# https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#chrome-headless-doesnt-launch-on-unix
RUN apt-get update \
     && apt-get install -y \
        cmake \
        ca-certificates \
        fonts-liberation \
        libappindicator3-1 \
        libasound2 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libc6 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libexpat1 \
        libfontconfig1 \
        libgbm1 \
        libgcc1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libstdc++6 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxrandr2 \
        libxrender1 \
        libxss1 \
        libxtst6 \
        lsb-release \
        wget \
        xdg-utils

# Installs the command "sha3sum", which is used check the download integrity of sqlite source.
RUN apt-get install -y libdigest-sha3-perl


ARG USER_ID
ARG GROUP_ID

RUN mkdir -p /install
RUN mkdir -p /install/lib


##################################################################
# git config
##################################################################
RUN git config --global advice.detachedHead false

##################################################################
# sqlite
##################################################################
RUN mkdir -p /opt/sqlite/src && \
    git clone --branch v1.6.2 --depth 1 https://github.com/sql-js/sql.js  /opt/sqlite/src

RUN cd /opt/sqlite/src && \
    make


##################################################################
# xtl
##################################################################
RUN mkdir -p /opt/xtl/build && \
    git clone --branch 0.7.2 --depth 1 https://github.com/xtensor-stack/xtl.git  /opt/xtl/src

RUN cd /opt/xtl/build && \
    emcmake cmake ../src/   -DCMAKE_INSTALL_PREFIX=/install

RUN cd /opt/xtl/build && \
    emmake make -j8 install


##################################################################
# nloman json
##################################################################
RUN mkdir -p /opt/nlohmannjson/build && \
    git clone --branch v3.9.1 --depth 1 https://github.com/nlohmann/json.git  /opt/nlohmannjson/src

RUN cd /opt/nlohmannjson/build && \
    emcmake cmake ../src/   -DCMAKE_INSTALL_PREFIX=/install -DJSON_BuildTests=OFF

RUN cd /opt/nlohmannjson/build && \
    emmake make -j8 install



##################################################################
# xpropery
##################################################################
RUN mkdir -p /opt/xproperty/build && \
    git clone --branch 0.11.0 --depth 1 https://github.com/jupyter-xeus/xproperty.git  /opt/xproperty/src

RUN cd /opt/xproperty/build && \
    emcmake cmake ../src/   \
    -Dxtl_DIR=/install/share/cmake/xtl \
    -DCMAKE_INSTALL_PREFIX=/install

RUN cd /opt/xproperty/build && \
    emmake make -j8 install


##################################################################
# xeus itself
##################################################################
# ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" skipcache

RUN mkdir -p /opt/xeus &&  \
    git clone --branch 2.3.0  --depth 1   https://github.com/jupyter-xeus/xeus.git   /opt/xeus
RUN mkdir -p /xeus-build && cd /xeus-build  && ls &&\
    emcmake cmake  /opt/xeus \
        -DCMAKE_INSTALL_PREFIX=/install \
        -Dnlohmann_json_DIR=/install/lib/cmake/nlohmann_json \
        -Dxtl_DIR=/install/share/cmake/xtl \
        -DXEUS_EMSCRIPTEN_WASM_BUILD=ON
RUN cd /xeus-build && \
    emmake make -j8 install





##################################################################
# xwidgets
##################################################################
RUN mkdir -p /opt/xwidgets/build && \
    git clone --branch  0.26.1 --depth 1 https://github.com/jupyter-xeus/xwidgets.git  /opt/xwidgets/src

RUN cd /opt/xwidgets/build && \
    emcmake cmake ../src/  \
    -Dxtl_DIR=/install/share/cmake/xtl \
    -Dxproperty_DIR=/install/lib/cmake/xproperty \
    -Dnlohmann_json_DIR=/install/lib/cmake/nlohmann_json \
    -Dxeus_DIR=/install/lib/cmake/xeus \
    -DXWIDGETS_BUILD_SHARED_LIBS=OFF \
    -DXWIDGETS_BUILD_STATIC_LIBS=ON  \
    -DCMAKE_INSTALL_PREFIX=/install \
    -DCMAKE_CXX_FLAGS="-Oz -flto"
RUN cd /opt/xwidgets/build && \
    emmake make -j8 install


##################################################################
# xvega
##################################################################
RUN mkdir -p /opt/xvega/build && \
    git clone --branch  0.0.10 --depth 1 https://github.com/QuantStack/xvega.git  /opt/xvega/src

RUN cd /opt/xvega/build && \
    emcmake cmake ../src/  \
    -Dxtl_DIR=/install/share/cmake/xtl \
    -Dxproperty_DIR=/install/lib/cmake/xproperty \
    -Dnlohmann_json_DIR=/install/lib/cmake/nlohmann_json \
    -Dxeus_DIR=/install/lib/cmake/xeus \
    -DXVEGA_BUILD_SHAREDS=OFF \
    -DXVEGA_BUILD_STATICS=ON  \
    -DCMAKE_INSTALL_PREFIX=/install \
    -DCMAKE_CXX_FLAGS="-Oz -flto"
RUN cd /opt/xvega/build && \
    emmake make -j8 install



# ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" skipcache

##################################################################
# xvega-binings
##################################################################
# RUN mkdir -p /opt/xvega-bindings/build && \
#     git clone --branch  0.0.10 --depth 1 https://github.com/jupyter-xeus/xvega-bindings.git  /opt/xvega-bindings/src

RUN mkdir -p /opt/xvega-bindings/build && \
    git clone -b no_var https://github.com/DerThorsten/xvega-bindings.git  /opt/xvega-bindings/src

RUN cd /opt/xvega-bindings/build && \
    emcmake cmake ../src/  \
    -Dxtl_DIR=/install/share/cmake/xtl \
    -Dxvega_DIR=/install/lib/cmake/xvega \
    -Dxeus_DIR=/install/lib/cmake/xeus \
    -Dxproperty_DIR=/install/lib/cmake/xproperty \
    -Dnlohmann_json_DIR=/install/lib/cmake/nlohmann_json \
    -Dxeus_DIR=/install/lib/cmake/xeus \
    -DCMAKE_INSTALL_PREFIX=/install \
    -DCMAKE_CXX_FLAGS="-Oz -flto"
RUN cd /opt/xvega-bindings/build && \
    emmake make -j8 install



##################################################################
# tabulate
##################################################################
RUN mkdir -p /opt/tabulate/build && \
    git clone --branch v1.4 --depth 1 https://github.com/p-ranav/tabulate.git  /opt/tabulate/src

RUN cd /opt/tabulate/build && \
    emcmake cmake ../src/ \
        -DCMAKE_INSTALL_PREFIX=/install \
        -DJSON_BuildTests=OFF

RUN cd /opt/tabulate/build && \
    emmake make -j8 install

##################################################################
# sqlitecpp
##################################################################
RUN mkdir -p /opt/sqlitecpp/build && \
    git clone --branch 3.1.1 --depth 1 https://github.com/SRombauts/SQLiteCpp.git  /opt/sqlitecpp/src

RUN cd /opt/sqlitecpp/build && \
    emcmake cmake ../src/ \
        -DCMAKE_INSTALL_PREFIX=/install \
        -DJSON_BuildTests=OFF\
        -DSQLITECPP_USE_STACK_PROTECTION=OFF\
        -DCMAKE_CXX_FLAGS="-fno-stack-protector -U_FORTIFY_SOURCE "\
        -DCMAKE_C_FLAGS="-fno-stack-protector -U_FORTIFY_SOURCE "

RUN cd /opt/sqlitecpp/build && \
    emmake make -j8 install





##################################################################
# xeus-sqlite
##################################################################

RUN mkdir -p /opt/xeus-sqlite/
#RUN git clone  --branch  0.6.1 --depth 1 https://github.com/jupyter-xeus/xeus-sqlite.git   /opt/xeus-sqlite

COPY . /opt/xeus-sqlite


RUN mkdir -p /xeus-sqlite-build && cd /xeus-sqlite-build  && ls && \
    emcmake cmake  /opt/xeus-sqlite \
        -DXSQL_EMSCRIPTEN_WASM_BUILD=ON \
        -DCMAKE_INSTALL_PREFIX=/install \
        -Dnlohmann_json_DIR=/install/lib/cmake/nlohmann_json \
        -Dxtl_DIR=/install/share/cmake/xtl \
        -Dxproperty_DIR=/install/lib/cmake/xproperty \
        -Dxwidgets_DIR=/install/lib/cmake/xwidgets \
        -DSQLite3_LIBRARY=/install/lib/libsqlite3.a\
        -DSQLite3_INCLUDE_DIR=/install/include/\
        -Dtabulate_DIR=/install/lib/cmake/tabulate\
        -DSQLiteCpp_DIR=/install/lib/cmake/SQLiteCpp\
        -Dxvega_DIR=/install/lib/cmake/xvega \
        -Dxvega-bindings_DIR=/install/lib/cmake/xvega-bindings \
        -DXSQL_USE_SHARED_XEUS=OFF\
        -DXSQL_BUILD_SHARED=OFF\
        -DXSQL_BUILD_STATIC=ON\
        -DXSQL_BUILD_XSQLITE_EXECUTABLE=OFF\
        -Dxeus_DIR=/install/lib/cmake/xeus \
        -DCMAKE_CXX_FLAGS="-Oz -flto"

RUN cd /xeus-sqlite-build && \
    emmake make -j8

