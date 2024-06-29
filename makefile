tcore:
	forge test -vv --match-contract CallETHTest --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703 --match-test test_swap_price_up_then_rebalance
tavs:
	forge test -vv --match-contract TestAVSRebalancingCall --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703

spell:
	cspell "**/*.*"