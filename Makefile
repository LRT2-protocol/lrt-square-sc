-include .env

.PHONY: all test clean deploy-anvil extract-abi

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install-forge-dependencies :; forge install

# Update Dependencies
update:; forge update

build:; forge --version && forge build --sizes

test :; forge test -vvv 

snapshot :; forge snapshot

install-node-dependencies:; yarn install --immutable --immutable-cache --check-cache
