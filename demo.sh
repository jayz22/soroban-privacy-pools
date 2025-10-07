#!/bin/bash
set -e
echo "🚀 Starting Privacy Pool Demo..."

NETWORK=testnet # testnet, local
TOKEN_ADDRESS=CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC # XLM token address on testnet

# Check prerequisites
echo "🔍 Checking prerequisites..."
command -v jq >/dev/null 2>&1 || { echo "❌ Error: jq is required but not installed. Please install jq first."; exit 1; }
command -v soroban >/dev/null 2>&1 || { echo "❌ Error: soroban CLI is required but not installed."; exit 1; }
# Fund demo_user account if needed
echo "🏦 Ensuring demo_user account is funded..."
soroban keys fund demo_user --network $NETWORK > /dev/null 2>&1 || echo "⚠️  demo_user may already be funded"
# Step 1: Deploy contract
echo "📦 Deploying contract..."
cargo build --target wasm32v1-none --release -p privacy-pools || { echo "❌ Error: Failed to build contract"; exit 1; }
soroban contract optimize --wasm target/wasm32v1-none/release/privacy_pools.wasm --wasm-out target/wasm32v1-none/release/privacy_pools.optimized.wasm || { echo "❌ Error: Failed to optimize WASM"; exit 1; }
# Convert verification key to hex format and extract it
echo "🔑 Converting verification key..."
cargo run --bin circom2soroban vk circuits/output/main_verification_key.json > vk_hex.txt || { echo "❌ Error: Failed to convert verification key"; exit 1; }
VK_HEX=$(cat vk_hex.txt | grep -o '[0-9a-f]*$')
if [ -z "$VK_HEX" ]; then
    echo "❌ Error: Failed to extract verification key hex"
    exit 1
fi

echo "🚀 Deploying contract to $NETWORK..."
soroban contract deploy --wasm target/wasm32v1-none/release/privacy_pools.optimized.wasm --source demo_user --network $NETWORK -- --vk_bytes $VK_HEX --token_address $TOKEN_ADDRESS || { echo "❌ Error: Failed to deploy contract"; exit 1; }
# Save the contract ID for later use
echo ""
echo "📋 Please paste the contract ID from the deployment above:"
read CONTRACT_ID
if [ -z "$CONTRACT_ID" ]; then
    echo "❌ Error: No contract ID provided"
    exit 1
fi
echo "✅ Contract ID set to: $CONTRACT_ID"
# Step 2: Generate coin
echo "🪙 Generating coin..."
cargo run --bin coinutils generate demo_pool demo_coin.json || { echo "❌ Error: Failed to generate coin"; exit 1; }
COMMITMENT_HEX=$(cat demo_coin.json | jq -r '.commitment_hex' | sed 's/^0x//')
if [ -z "$COMMITMENT_HEX" ]; then
    echo "❌ Error: Failed to extract commitment hex"
    exit 1
fi
echo "Generated coin with commitment: $COMMITMENT_HEX"
# Step 3: Deposit
echo "💰 Depositing coin..."
soroban contract invoke --id $CONTRACT_ID --source demo_user --network $NETWORK -- deposit --from demo_user --commitment $COMMITMENT_HEX || { echo "❌ Error: Failed to deposit coin"; exit 1; }
echo "Deposit successful!"
# Step 4: Check balance
echo "📊 Checking balance..."
soroban contract invoke --id $CONTRACT_ID --source demo_user --network $NETWORK -- get_balance || { echo "❌ Error: Failed to get balance"; exit 1; }
# Step 5: Create state file and association set
echo "📋 Creating state file..."
COMMITMENT=$(cat demo_coin.json | jq -r '.coin.commitment')
echo "{
  \"commitments\": [
    \"$COMMITMENT\"
  ],
  \"scope\": \"demo_pool\"
}" > demo_state.json

echo "🏷️  Creating association set..."
LABEL=$(cat demo_coin.json | jq -r '.coin.label')
cargo run --bin coinutils updateAssociation demo_association.json "$LABEL" || { echo "❌ Error: Failed to create association set"; exit 1; }

echo "🔐 Creating withdrawal proof..."
cargo run --bin coinutils withdraw demo_coin.json demo_state.json demo_association.json withdrawal_input.json || { echo "❌ Error: Failed to create withdrawal input"; exit 1; }
echo "📝 Generating witness and proof..."
cd circuits
node build/main_js/generate_witness.js build/main_js/main.wasm ../withdrawal_input.json witness.wtns || { echo "❌ Error: Failed to generate witness"; exit 1; }
snarkjs groth16 prove output/main_final.zkey witness.wtns proof.json public.json || { echo "❌ Error: Failed to generate proof"; exit 1; }
cd ..
echo "🔄 Converting proof for Soroban..."
cargo run --bin circom2soroban proof circuits/proof.json > proof_hex.txt || { echo "❌ Error: Failed to convert proof"; exit 1; }
cargo run --bin circom2soroban public circuits/public.json > public_hex.txt || { echo "❌ Error: Failed to convert public signals"; exit 1; }
PROOF_HEX=$(sed -n '/^Proof Hex encoding:/{n;p;}' proof_hex.txt | tr -d '[:space:]' | sed -E 's/^0x//i')
PUBLIC_HEX=$(cat public_hex.txt | grep -o '[0-9a-f]*$')
if [ -z "$PROOF_HEX" ] || [ -z "$PUBLIC_HEX" ]; then
    echo "❌ Error: Failed to extract proof or public signals"
    exit 1
fi

# Extract association root from public signals and set it in the contract
echo "🔗 Setting association root in contract..."
ASSOCIATION_ROOT_HEX=$(echo "$PUBLIC_HEX" | tail -c 65) # Last 64 hex chars (32 bytes) for association root
soroban contract invoke --id $CONTRACT_ID --source demo_user --network $NETWORK -- set_association_root --admin demo_user --association_root $ASSOCIATION_ROOT_HEX || { echo "❌ Error: Failed to set association root"; exit 1; }
# Step 6: Withdraw
echo "💸 Withdrawing coin..."
soroban contract invoke --id $CONTRACT_ID --source demo_user --network $NETWORK -- withdraw --to demo_user --proof_bytes "$PROOF_HEX" --pub_signals_bytes "$PUBLIC_HEX" || { echo "❌ Error: Failed to withdraw coin"; exit 1; }
echo "Withdrawal successful!"
# Step 7: Verify
echo "✅ Verifying withdrawal..."
soroban contract invoke --id $CONTRACT_ID --source demo_user --network $NETWORK -- get_nullifiers || { echo "❌ Error: Failed to get nullifiers"; exit 1; }
soroban contract invoke --id $CONTRACT_ID --source demo_user --network $NETWORK -- get_balance || { echo "❌ Error: Failed to get final balance"; exit 1; }
echo "🎉 Demo completed successfully!"

