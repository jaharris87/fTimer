# Convenience wrapper — delegates to CMake
#
# Usage:
#   make            Build the default serial path
#   make mpi        Build the documented MPI path (defaults FC=mpifort)
#   make openmp     Build the documented OpenMP path (defaults FC=gfortran)
#   make test       Build + run default smoke tests
#   make clean      Remove build directory
#   make install    Install to CMAKE_INSTALL_PREFIX

BUILD_DIR   ?= build
CMAKE_FLAGS ?=
NPROC       := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

.PHONY: all mpi openmp test clean install

all:
	cmake -B $(BUILD_DIR) $(CMAKE_FLAGS)
	cmake --build $(BUILD_DIR) -j$(NPROC)

mpi:
	FC=$${FC:-mpifort} cmake -B $(BUILD_DIR) -DFTIMER_USE_MPI=ON $(CMAKE_FLAGS)
	cmake --build $(BUILD_DIR) -j$(NPROC)

openmp:
	FC=$${FC:-gfortran} cmake -B $(BUILD_DIR) -DFTIMER_USE_OPENMP=ON $(CMAKE_FLAGS)
	cmake --build $(BUILD_DIR) -j$(NPROC)

test: all
	ctest --test-dir $(BUILD_DIR) --output-on-failure

clean:
	rm -rf $(BUILD_DIR)

install: all
	cmake --install $(BUILD_DIR)
