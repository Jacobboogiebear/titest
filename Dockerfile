# Build llvm-cbe .deb package
FROM ubuntu:22.04 AS llvm-cbe-builder

# Add Mantic repository to install
RUN echo "deb http://archive.ubuntu.com/ubuntu/ mantic main restricted" >> /etc/apt/sources.list &&\
	echo "deb http://archive.ubuntu.com/ubuntu/ mantic universe" >> /etc/apt/sources.list

# Install dependencies
RUN apt-get update -y &&\
	apt-get install -t mantic llvm-17 llvm-17-dev clang-17 python3.12 -y &&\
	apt-get install -t jammy cmake binutils git gcc g++ ninja-build -y

# Setup for builds
RUN mkdir /build
WORKDIR /build/

# Clone llvm-cbe repository at commit 5a3f239c2842275deb4b8e13c8811c1ca3a29bd7
RUN git clone https://github.com/JuliaComputing/llvm-cbe.git --depth 1
WORKDIR /build/llvm-cbe/
RUN git reset --hard 5a3f239c2842275deb4b8e13c8811c1ca3a29bd7

# Build llvm-cbe
RUN mkdir build
WORKDIR /build/llvm-cbe/build/
RUN cmake -S .. -G "Unix Makefiles"
RUN make llvm-cbe

# Setup for packaging
RUN mkdir -p /deb/usr/bin/ &&\
	mkdir /deb/DEBIAN/ &&\
	touch /deb/DEBIAN/control

# Copy binary
RUN cp /build/llvm-cbe/build/tools/llvm-cbe/llvm-cbe /deb/usr/bin/

# Create control file
RUN echo "Package: llvm-cbe" >> /deb/DEBIAN/control &&\
	echo "Version: 1.0" >> /deb/DEBIAN/control &&\
	echo "Maintainer: JuliaHubOSS" >> /deb/DEBIAN/control &&\
	echo "Architecture: all" >> /deb/DEBIAN/control &&\
	echo "Description: LLVM CBE" >> /deb/DEBIAN/control &&\
	echo "Depends: llvm-17, clang-17, llvm-17-dev" >> /deb/DEBIAN/control

# Package
RUN mkdir /packaged/
WORKDIR /packaged/
RUN dpkg-deb --build /deb/ llvm-cbe.deb

# Create export directory
RUN mkdir /export/

# Copy debian package
RUN cp /packaged/llvm-cbe.deb /export/

# ------------------------------------------------

# Compiles rust dependencies
FROM ubuntu:22.04 AS rust-dep-builder

# Install dependencies
RUN apt-get update &&\
	apt-get install binutils gcc build-essential curl -y

# Setup rust for compiling
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup default nightly &&\
	rustup component add rust-src --toolchain nightly-x86_64-unknown-linux-gnu

# Install gcc-avr + avr-libc for rust compiling of AVR target
RUN apt-get install gcc-avr avr-libc -y

# Create cargo project
RUN mkdir -p /deps/src &&\
	mkdir -p /deps/.cargo
RUN touch /deps/Cargo.toml &&\
	echo '[package]' >> /deps/Cargo.toml &&\
	echo 'name = "phony"' >> /deps/Cargo.toml &&\
	echo 'version = "0.0.0"' >> /deps/Cargo.toml
RUN touch /deps/src/main.rs &&\
	echo '#![no_std]' >> /deps/src/main.rs &&\
	echo '#![no_main]' >> /deps/src/main.rs &&\
	echo '#[no_mangle]' >> /deps/src/main.rs &&\
	echo 'pub extern fn main() {}' >> /deps/src/main.rs &&\
	echo 'use core::panic::PanicInfo;' >> /deps/src/main.rs &&\
	echo '#[allow(unconditional_recursion)]' >> /deps/src/main.rs &&\
	echo '#[panic_handler]' >> /deps/src/main.rs &&\
	echo 'fn panic_handler_phony(info: &PanicInfo) -> ! { panic_handler_phony(info) }' >> /deps/src/main.rs
RUN touch /deps/.cargo/config.toml &&\
	echo '[build]' >> /deps/.cargo/config.toml &&\
	echo 'target = "avr-unknown-gnu-atmega328"' >> /deps/.cargo/config.toml &&\
	echo '[unstable]' >> /deps/.cargo/config.toml &&\
	echo 'build-std = ["core"]' >> /deps/.cargo/config.toml &&\
	echo '[profile.dev]' >> /deps/.cargo/config.toml &&\
	echo 'panic = "abort"' >> /deps/.cargo/config.toml &&\
	echo '[profile.release]' >> /deps/.cargo/config.toml &&\
	echo 'panic = "abort"' >> /deps/.cargo/config.toml
WORKDIR /deps/

# Compile dependencies
RUN cargo build --release

# ------------------------------------------------

# Compiles rust to C
FROM ubuntu:22.04 AS rust-to-c-compiler

# Setup and install LLVM-CBE dependency
RUN echo "deb http://archive.ubuntu.com/ubuntu/ mantic main restricted" >>/etc/apt/sources.list &&\
	echo "deb http://archive.ubuntu.com/ubuntu/ mantic universe" >>/etc/apt/sources.list &&\
	apt-get update &&\
	apt-get install llvm-17 clang-17 llvm-17-dev -y
RUN mkdir /res/
COPY --from=llvm-cbe-builder /export/llvm-cbe.deb /res/llvm-cbe.deb
RUN apt-get install /res/llvm-cbe.deb -y

# Copy rlib dependencies
RUN mkdir /project/ &&\
	mkdir /deps/
COPY --from=rust-dep-builder /deps/target/avr-unknown-gnu-atmega328/release/deps/*.rlib /deps/
WORKDIR /project/

# Setup rust for compiling
RUN apt-get update &&\
	apt-get install binutils gcc build-essential curl -y
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup default nightly &&\
	rustup component add rust-src --toolchain nightly-x86_64-unknown-linux-gnu

# Install python for transpile script
RUN apt-get install python3.12 -y

# Copy rust source code
COPY ./src/ /project/src/
COPY ./Cargo.toml /project/Cargo.toml

# Copy builder.py
COPY ./res/builder.py /project/builder.py

# Compile rust code to LLVM-IR
RUN rustc --emit=llvm-ir -C opt-level=3 -C embed-bitcode=no --target avr-unknown-gnu-atmega328 -C panic=abort -L dependency=/deps --extern noprelude:compiler_builtins=/deps/$(ls /deps/ | grep libcompiler_builtins) --extern noprelude:core=/deps/$(ls /deps/ | grep libcore) -Z unstable-options ./src/main.rs -o ./rust.ll

# Convert LLVM-IR to C code
RUN llvm-cbe --cbe-declare-locals-late ./rust.ll -o ./main.c

# Transpile C code slightly
RUN python3.12 /project/builder.py

# ------------------------------------------------

# Create and compile final binary
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update &&\
	apt-get install wget binutils make -y

# Setup project directory
RUN mkdir -p /project/src/
WORKDIR /project/

# Download CEdev toolchain
RUN wget https://github.com/CE-Programming/toolchain/releases/download/v11.2/CEdev-Linux.tar.gz
RUN tar -xvf ./CEdev-Linux.tar.gz
RUN cp -r ./CEdev/* /usr/

# Copy C code
COPY --from=rust-to-c-compiler /project/main.c /project/src/main.c

# Copy makefile and icon
COPY ./res/icon.png /project/icon.png
COPY ./res/Makefile /project/Makefile

# Build binary
RUN make

# Cleanup for better image size
RUN rm -rf ./CEdev ./CEdev-Linux.tar.gz

# Make final export folder
RUN mkdir /export/

# Copy and set final binary
RUN cp ./bin/DEMO.8xp /export/
WORKDIR /export/

CMD [ "/bin/bash", "exit" ]