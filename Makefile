.PHONY: update build size inspect test snap clean lint
build 			:; forge soldeer update; forge build
compile 		:; forge compile
size 			:; forge build --sizes
inspect 		:; forge inspect ${contract} storage-layout --pretty
test 			:; forge test -vv
traces		 	:; forge test -vvvv
snap 			:; forge coverage --report lcov; forge snapshot
clean 			:; forge clean
lint 			:; forge fmt
fmt 			:; forge fmt
add		    	:; forge soldeer install ${dependency}
remove			:; forge soldeer uninstall ${dependency}
deploy-mainnet 	:; forge clean && source .env && forge script --chain-id 2192 script/Deploy.s.sol --rpc-url $$SNAXCHAIN_MAINNET_HTTP_URL --broadcast --verify --verifier blockscout --verifier-url https://explorer.snaxchain.io/api/
deploy-testnet 	:; forge clean && source .env && forge script --chain-id 13001 script/Deploy.s.sol --rpc-url $$SNAXCHAIN_TESTNET_HTTP_URL --broadcast --verify --verifier blockscout --verifier-url 'https://explorer-snaxchain-testnet-0.t.conduit.xyz/api/'