# Use bash as shell
SHELL := /bin/bash

# Load environment variables
ifneq (,$(wildcard ./.env))
	include .env
	export
endif

# Phony targets
.PHONY: install clean build test format docs snapshot diff deploy

# Default: install deps, clean build outputs, format code, build code, run tests
all: install clean format build test

# Install dependencies
install:
	@forge install

# Clean build outputs
clean:
	@forge clean

# Build contracts + tests
build:
	@forge build
	@cp -r compiled/. out/

# Run tests
test:
	@forge test -vvv

# Execute scripts/deploy given environment variables
deploy:
	@forge script scripts/Deploy.sol:Deploy \
		--broadcast \
		--optimize \
		--optimizer-runs 1000000 \
		--extra-output-files abi \
		--rpc-url $(RPC_URL)

# Save gas snapshot
snapshot:
	@forge snapshot

# Compare current gas profile to saved gas snapshot
diff:
	@forge snapshot --diff

# Format contracts
format:
	@forge fmt

# Generate and serve docs
docs:
	@forge doc --build
	@open http://localhost:4000
	@forge doc --serve --port 4000
