# Copyright 2022 The KubeVela Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

all: build

# ===== BUILD =====

build-dirs:
	mkdir -p "$(GOCACHE)/gocache" \
	         "$(GOCACHE)/gomodcache" \
	         "$(DIST)"

build: # @HELP build binary for current platform
build: gen-dockerignore build-dirs
	docker run                               \
	    -i                                   \
	    --rm                                 \
	    -u $$(id -u):$$(id -g)               \
	    -v $$(pwd):/src                      \
	    -w /src                              \
	    -v $$(pwd)/$(GOCACHE):/cache         \
	    --env GOCACHE="/cache/gocache"       \
	    --env GOMODCACHE="/cache/gomodcache" \
	    --env ARCH="$(ARCH)"                 \
	    --env OS="$(OS)"                     \
	    --env VERSION="$(VERSION)"           \
	    --env DEBUG="$(DEBUG)"               \
	    --env OUTPUT="$(OUTPUT)"             \
	    --env GOFLAGS="$(GOFLAGS)"           \
	    --env GOPROXY="$(GOPROXY)"           \
	    --env HTTP_PROXY="$(HTTP_PROXY)"     \
	    --env HTTPS_PROXY="$(HTTPS_PROXY)"   \
	    $(BUILD_IMAGE)                       \
	    ./build/build.sh $(ENTRY)

# INTERNAL: build-<os>_<arch> to build for a specific platform
build-%:
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
	    build                                \
	    --no-print-directory                 \
	    GOOS=$(firstword $(subst _, ,$*))    \
	    GOARCH=$(lastword $(subst _, ,$*))   \
	    FULL_NAME=1

all-build: # @HELP build binaries for all platforms
all-build: $(addprefix build-, $(subst /,_, $(BIN_PLATFORMS)))

# ===== PACKAGE =====

package: # @HELP build and package binary for current platform
package: build
	mkdir -p "$(BIN_VERBOSE_DIR)"
	cp LICENSE "$(BIN_VERBOSE_DIR)/LICENSE"
	cp "$(OUTPUT)" "$(BIN_VERBOSE_DIR)/$(BIN_BASENAME)"
	echo "# PACKAGE compressing $(BIN) to $(BIN_VERBOSE_DIR)/$(PKG_FULLNAME)"
	cd $(BIN_VERBOSE_DIR) &&              \
	    if [ "$(OS)" == "windows" ]; then \
	        zip "$(PKG_FULLNAME)" "$(BIN_BASENAME)" LICENSE;     \
	    else                                                     \
	        tar czf "$(PKG_FULLNAME)" "$(BIN_BASENAME)" LICENSE; \
	    fi;                                                      \
	    sha256sum "$(PKG_FULLNAME)" >> "$(BIN)-$(VERSION)-checksums.txt"; \
	    rm -f LICENSE "$(BIN_BASENAME)"
	echo "# PACKAGE checksum saved to $(BIN_VERBOSE_DIR)/$(BIN)-$(VERSION)-checksums.txt"

# INTERNAL: package-<os>_<arch> to build and package for a specific platform
package-%:
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
	    package                              \
	    --no-print-directory                 \
	    GOOS=$(firstword $(subst _, ,$*))    \
	    GOARCH=$(lastword $(subst _, ,$*))   \
	    FULL_NAME=1

all-package: # @HELP build and package binaries for all platforms
all-package: $(addprefix package-, $(subst /,_, $(BIN_PLATFORMS)))
# overwrite previous checksums
	cd "$(BIN_VERBOSE_DIR)" && sha256sum *{.tar.gz,.zip} > "$(BIN)-$(VERSION)-checksums.txt"
	echo "# PACKAGE all checksums saved to $(BIN_VERBOSE_DIR)/$(BIN)-$(VERSION)-checksums.txt"

# ===== CONTAINERS =====

container-build: # @HELP build container image for current platform
container-build: build-linux_$(ARCH)
	printf "# CONTAINER repotags: %s\ttarget: %s/%s\tbinaryversion: %s\n" "$(IMAGE_REPO_TAGS)" "linux" "$(ARCH)" "$(VERSION)"
	if [ "$(OS)" != "linux" ]; then \
	    echo "# CONTAINER warning: you have set target os to $(OS), but container target os will always be linux"; \
	fi; \
	TMPFILE=Dockerfile && \
	    sed 's/$${BIN}/$(BIN)/g' Dockerfile.in > $${TMPFILE} && \
	    DOCKER_BUILDKIT=1                      \
	    docker build                           \
	    -f $${TMPFILE}                         \
	    --build-arg "ARCH=$(ARCH)"             \
	    --build-arg "OS=linux"                 \
	    --build-arg "VERSION=$(VERSION)"       \
	    --build-arg "BASE_IMAGE=$(BASE_IMAGE)" \
	    $(addprefix -t ,$(IMAGE_REPO_TAGS)) .

container-push: # @HELP push built container image to all repos
container-push: $(addprefix container-push-, $(subst :,=, $(subst /,_, $(IMAGE_REPO_TAGS))))

# INTERNAL: container-push-example.com_library_name=tag to push a specific image
container-push-%:
	echo "# Pushing $(subst =,:,$(subst _,/,$*))"
	docker push $(subst =,:,$(subst _,/,$*))

BUILDX_PLATFORMS := $(shell echo "$(IMAGE_PLATFORMS)" | sed 's/ /,/g')

all-container-build-push: # @HELP build and push container images for all platforms
all-container-build-push: $(addprefix build-, $(subst /,_, $(IMAGE_PLATFORMS)))
	echo -e "# Building and pushing images for platforms $(IMAGE_PLATFORMS)"
	echo -e "# target: $(OS)/$(ARCH)\tversion: $(VERSION)\ttags: $(IMAGE_REPO_TAGS)"
	TMPFILE=Dockerfile && \
	    sed 's/$${BIN}/$(BIN)/g' Dockerfile.in > $${TMPFILE} && \
	    docker buildx build --push             \
	    -f $${TMPFILE}                         \
	    --platform "$(BUILDX_PLATFORMS)"       \
	    --build-arg "VERSION=$(VERSION)"       \
	    --build-arg "BASE_IMAGE=$(BASE_IMAGE)" \
	    $(addprefix -t ,$(IMAGE_REPO_TAGS)) .

# ===== MISC =====

# Optional variable to pass arguments to sh
# Example: make shell CMD="-c 'date'"
CMD ?=

shell: # @HELP launches a shell in the containerized build environment
shell: build-dirs
	echo "# launching a shell in the containerized build environment"
	docker run                               \
	    -it                                  \
	    --rm                                 \
	    -u $$(id -u):$$(id -g)               \
	    -v $$(pwd):/src                      \
	    -w /src                              \
	    -v $$(pwd)/$(GOCACHE):/cache         \
	    --env GOCACHE="/cache/gocache"       \
	    --env GOMODCACHE="/cache/gomodcache" \
	    --env ARCH="$(ARCH)"                 \
	    --env OS="$(OS)"                     \
	    --env VERSION="$(VERSION)"           \
	    --env DEBUG="$(DEBUG)"               \
	    --env OUTPUT="$(OUTPUT)"             \
	    --env GOFLAGS="$(GOFLAGS)"           \
	    --env GOPROXY="$(GOPROXY)"           \
	    --env HTTP_PROXY="$(HTTP_PROXY)"     \
	    --env HTTPS_PROXY="$(HTTPS_PROXY)"   \
	    $(BUILD_IMAGE)                       \
	    /bin/sh $(CMD)

# Generate a dockerignore file to ignore everything except
# current build output directory. This is useful because
# when building a container, we only need the final binary.
# So we can avoid copying unnecessary files to the build
# context.
gen-dockerignore:
	echo -e "*\n!$(BIN_VERBOSE_DIR)" > .dockerignore

clean: # @HELP clean built binaries
clean:
	rm -rf $(DIST)/$(BIN)*

all-clean: # @HELP clean built binaries, build cache, and helper tools
all-clean: clean
	test -d $(GOCACHE) && chmod -R u+w $(GOCACHE) || true
	rm -rf $(GOCACHE) $(DIST)

version: # @HELP output the version string
version:
	echo $(VERSION)

imageversion: # @HELP output the container image version
imageversion:
	echo $(IMAGE_TAG)

binaryname: # @HELP output current artifact binary name
binaryname:
	echo $(BIN_FULLNAME)

variables: # @HELP print makefile variables
variables:
	echo "VARIABLES:"
	echo "  OUTPUT            $(OUTPUT)"
	echo "  VERSION           $(VERSION)"
	echo "  CURRENT_OS        $(OS)"
	echo "  CURRENT_ARCH      $(ARCH)"
	echo "  BIN_PLATFORMS     $(BIN_PLATFORMS)"
	echo "  IMAGE_TAG         $(IMAGE_TAG)"
	echo "  IMAGE_REPOS       $(IMAGE_REPOS)"
	echo "  IMAGE_REPO_TAGS   $(IMAGE_REPO_TAGS)"
	echo "  IMAGE_PLATFORMS   $(IMAGE_PLATFORMS)"
	echo "  DEBUG             $(DEBUG)"
	echo "  GOPROXY           $(GOPROXY)"
	echo "  GOFLAGS           $(GOFLAGS)"

help: # @HELP print this message
help: variables
	echo "TARGETS:"
	grep -E '^.*: *# *@HELP' $(MAKEFILE_LIST)    \
	    | sed -E 's_.*.mk:__g'                   \
	    | awk '                                  \
	        BEGIN {FS = ": *# *@HELP"};          \
	        { printf "  %-25s %s\n", $$1, $$2 }; \
	    '
