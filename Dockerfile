FROM ubuntu:21.04

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        pkg-config tini build-essential git \
        ccache cmake ninja-build llvm clang clang-format clang-tidy curl python python3 \
        bison flex \
        brotli rsync \
        libssl-dev \
        libpthread-stubs0-dev \
        libboost-all-dev \
        firefox \
        wget gnupg ca-certificates procps libxss1 \
    && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/google.list

ARG EMSDK_VERSION="3.1.1"
RUN mkdir -p /opt/emsdk \
    && cd /opt/emsdk \
    && curl -SL https://github.com/emscripten-core/emsdk/archive/${EMSDK_VERSION}.tar.gz | tar -xz --strip-components=1 \
    && ./emsdk install ${EMSDK_VERSION} ccache-git-emscripten-64bit \
    && ./emsdk activate ${EMSDK_VERSION} ccache-git-emscripten-64bit \
    && /bin/bash ./emsdk_env.sh \
    && rm -rf ./emscripten/tag-*/tests \
    && rm -rf ./emscripten/tag-*/site \
    && rm -rf ./emscripten/tag-*/docs \
    && rm -rf ./zips \
    && find . -name "*.o" -exec rm {} \; \
    && find . -name "*.a" -exec rm {} \; \
    && find . -name "*.tmp" -exec rm {} \;

SHELL ["/bin/bash", "-c"]

ENV NVM_DIR=/opt/nvm
ARG NVM_VERSION="v0.38.0"
ARG NODE_VERSION="v16.1.0"
RUN mkdir -p /opt/nvm \
    && ls -lisah /opt/nvm \
    && curl https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash \
    && source ${NVM_DIR}/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm alias default ${NODE_VERSION} \
    && nvm use default \
    && npm install --global yarn

ARG FLATBUFFER_COMMIT="04b10f5a3a78aed27030a4e26dcf36921979114f"
RUN mkdir -p /tmp/flatbuffers/build /tmp/flatbuffers/install \
    && git clone https://github.com/google/flatbuffers /tmp/flatbuffers/repo \
    && cd /tmp/flatbuffers/repo \
    && git checkout ${FLATBUFFER_COMMIT} \
    && cmake -B /tmp/flatbuffers/build -S /tmp/flatbuffers/repo \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_CXX_FLAGS=-std=c++17 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DFLATBUFFERS_BUILD_FLATLIB=ON \
        -DFLATBUFFERS_BUILD_FLATC=ON \
        -DFLATBUFFERS_BUILD_FLATHASH=OFF \
        -DFLATBUFFERS_INSTALL=ON \
        -DFLATBUFFERS_BUILD_TESTS=OFF \
        -DFLATBUFFERS_BUILD_SHAREDLIB=OFF \
    && make -C /tmp/flatbuffers/build -j`nproc` install \
    && rm -rf /tmp/flatbuffers

ARG RUST_VERSION="1.56.0"
RUN export RUSTUP_HOME=/opt/rust \
    && export CARGO_HOME=/opt/rust \
    && curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain ${RUST_VERSION} -y \
    && export PATH=$PATH:/opt/rust/bin \
    && rustup target add wasm32-unknown-unknown \
    && cargo install wasm-pack wrangler
    

ENV AZURE_CONFIG_DIR=/opt/azure
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/azure

ARG BOOST_VERSION="1.74.0"
ARG BOOST_TARBALL="boost_1_74_0.tar.gz"
RUN curl -Lo /opt/boost.tar.gz "https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VERSION}/source/${BOOST_TARBALL}"

RUN source /opt/emsdk/emsdk_env.sh \
    && echo "export PATH=$PATH:/opt/rust/bin" >> /opt/env.sh \
    && echo "export EMSDK=$EMSDK" >> /opt/env.sh \
    && echo "export EM_CONFIG=$EM_CONFIG" >> /opt/env.sh \
    && echo "export EMSCRIPTEN=$EMSCRIPTEN" >> /opt/env.sh \
    && echo "export CARGO_HOME=/opt/rust" >> /opt/env.sh \
    && echo "export RUSTUP_HOME=/opt/rust" >> /opt/env.sh \
    && echo "export AZURE_CONFIG_DIR=/opt/azure" >> /opt/env.sh \
    && echo "export BOOST_ARCHIVE=/opt/boost.tar.gz" >> /opt/env.sh \
    && echo "source /opt/nvm/nvm.sh" >> /opt/env.sh \
    && printf '#!/bin/bash\nsource /opt/env.sh\nexec env "$@"\n' > /opt/entrypoint.sh \
    && chmod +x /opt/entrypoint.sh

ENTRYPOINT ["tini", "-v", "--", "/opt/entrypoint.sh"]
WORKDIR /github/workspace
