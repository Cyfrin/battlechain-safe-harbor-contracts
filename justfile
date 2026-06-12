set dotenv-load
set export

# Select with `just network=mainnet <recipe>` (defaults to testnet)
network := "testnet"

rpc := if network == "mainnet" {
    "https://mainnet.battlechain.com"
} else if network == "testnet" {
    "https://testnet.battlechain.com"
} else {
    error("unknown network: " + network + " (expected mainnet or testnet)")
}
verifier_url := if network == "mainnet" {
    "https://block-explorer-api.mainnet.battlechain.com/api"
} else {
    "https://block-explorer-api.testnet.battlechain.com/api"
}
chain_id := if network == "mainnet" { "626" } else { "627" }
default_account := env("ACCOUNT", "battlechain-testnet-deployer")
bc_flags := "--skip-simulation -g 200"
verify_flags := "--verify --verifier-url " + verifier_url + " --verifier custom --etherscan-api-key 1234"

# Deploy SafeHarborRegistry + AgreementFactory
deploy-safe-harbor account=default_account sender="${SENDER}":
    forge script script/Deploy.s.sol --rpc-url {{ rpc }} --broadcast --account {{ account }} --sender {{ sender }} {{ bc_flags }} {{ verify_flags }}

# Deploy AttackRegistry + BattleChainDeployer (requires SafeHarborRegistry + AgreementFactory addresses).
# The registry already knows the pre-computed AttackRegistry proxy address from initialization.
deploy-attack-registry safe_harbor_registry agreement_factory account=default_account sender="${SENDER}":
    forge script script/DeployAttackRegistry.s.sol --sig "run(address,address)" {{ safe_harbor_registry }} {{ agreement_factory }} --rpc-url {{ rpc }} --broadcast --account {{ account }} --sender {{ sender }} {{ bc_flags }} {{ verify_flags }}

deploy-mock-moderator attack_registry account=default_account sender="${SENDER}":
    forge script script/DeployMockRegistryModerator.s.sol --sig "run(address)" {{ attack_registry }} --rpc-url {{ rpc }} --broadcast --account {{ account }} --sender {{ sender }} {{ bc_flags }} {{ verify_flags }}

change-registry-moderator attack_registry new_moderator account=default_account sender="${SENDER}":
    forge script script/ChangeRegistryModerator.s.sol --sig "run(address,address)" {{ attack_registry }} {{ new_moderator }} --rpc-url {{ rpc }} --broadcast --account {{ account }} --sender {{ sender }} {{ bc_flags }}

deploy-createx account=default_account:
    forge create src/CreateX.sol:CreateX --rpc-url {{ rpc }} --broadcast --account {{ account }} --legacy

# Upgrade step 1: deploy new version-keyed implementations (broadcast as the deployer).
# Bump src/Version.sol first. Logs the upgradeToAndCall calldata for step 2.
upgrade-deploy-impls account=default_account sender="${SENDER}":
    forge script script/Upgrade.s.sol --sig "deployImplementations()" --rpc-url {{ rpc }} --broadcast --account {{ account }} --sender {{ sender }} {{ bc_flags }} {{ verify_flags }}

# Upgrade step 2: point the proxies at the new implementations (broadcast as the owner).
# On mainnet the owner is a multisig — execute the calldata logged by step 1 from the multisig instead.
upgrade-proxies safe_harbor_registry agreement_factory attack_registry account=default_account sender="${SENDER}":
    forge script script/Upgrade.s.sol --sig "upgradeProxies(address,address,address)" {{ safe_harbor_registry }} {{ agreement_factory }} {{ attack_registry }} --rpc-url {{ rpc }} --broadcast --account {{ account }} --sender {{ sender }} {{ bc_flags }}

# --skip-is-verified-check: the BattleChain explorer reports unverified contracts with a
# non-standard message that trips forge's pre-verification ABI lookup.
verify contract_address contract:
    forge verify-contract {{ contract_address }} {{ contract }} --chain-id {{ chain_id }} --verifier-url {{ verifier_url }} --verifier custom --etherscan-api-key "1234" --rpc-url {{ rpc }} --skip-is-verified-check --watch

certora-attack-registry:
    certoraRun certora/conf/AttackRegistry.conf --wait_for_results all

certora-agreement:
    certoraRun certora/conf/Agreement.conf --wait_for_results all

certora-all:
    certoraRun certora/conf/AttackRegistry.conf --wait_for_results all
    certoraRun certora/conf/Agreement.conf --wait_for_results all

certora-check:
    certoraRun certora/conf/AttackRegistry.conf --compilation_steps_only
    certoraRun certora/conf/Agreement.conf --compilation_steps_only

# add --priority-gas-price 200000000 if it's slow
# Current deployment addresses live in the README "Deployments" tables.
# Manual verification example: just verify <address> src/AttackRegistry.sol:AttackRegistry
