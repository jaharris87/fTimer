# Convenience wrapper — delegates to CMake
#
# Usage:
#   make            Build Phase 0 scaffold (serial)
#   make mpi        Build Phase 0 scaffold (MPI)
#   make test       Build + run default smoke tests
#   make clean      Remove build directory
#   make install    Install to CMAKE_INSTALL_PREFIX

BUILD_DIR   ?= build
CMAKE_FLAGS ?=
NPROC       := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

.PHONY: all mpi test clean install

all:
	cmake -B $(BUILD_DIR) $(CMAKE_FLAGS)
	cmake --build $(BUILD_DIR) -j$(NPROC)

mpi:
	cmake -B $(BUILD_DIR) -DFTIMER_USE_MPI=ON $(CMAKE_FLAGS)
	cmake --build $(BUILD_DIR) -j$(NPROC)

test: all
	ctest --test-dir $(BUILD_DIR) --output-on-failure

clean:
	rm -rf $(BUILD_DIR)

install: all
	cmake --install $(BUILD_DIR)
