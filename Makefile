all: build test

build: FORCE
	clear
	npx hardhat compile

test: build
	clear
	npx hardhat test

FORCE:
