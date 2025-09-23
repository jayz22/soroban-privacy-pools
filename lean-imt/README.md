# Lean Incremental Merkle Tree (LeanIMT)

A Rust implementation of a Lean Incremental Merkle Tree designed for use with Soroban smart contracts and compatible with the `merkleProof.circom` circuit.

## Overview

The LeanIMT is a specialized merkle tree implementation that follows specific design principles for efficient incremental updates and compatibility with zero-knowledge proof circuits. It's designed to work seamlessly with the privacy pools contract and the circom circuit implementation.

## Design Principles

The LeanIMT follows these key design principles:

1. **Every node with two children is the hash of its left and right nodes**
2. **Every node with one child has the same value as its child node**
3. **Tree is always built from leaves to root**
4. **Tree is always balanced by construction**
5. **Tree depth is dynamic and can increase with insertion of new leaves**

## Features

- **Incremental Updates**: Efficiently add new leaves without rebuilding the entire tree
- **Dynamic Depth**: Tree depth automatically adjusts based on the number of leaves
- **Proof Generation**: Generate merkle inclusion proofs for any leaf
- **Soroban Compatible**: Designed specifically for Stellar's Soroban smart contract platform
- **Circuit Compatible**: Matches the behavior expected by `merkleProof.circom`

## Usage

### Basic Usage

```rust
use lean_imt::LeanIMT;
use soroban_sdk::{Env, BytesN};

// Create a new tree
let env = Env::default();
let mut tree = LeanIMT::new(env.clone());

// Insert leaves
let leaf1 = BytesN::from_array(&env, &[1u8; 32]);
let leaf2 = BytesN::from_array(&env, &[2u8; 32]);

tree.insert(leaf1);
tree.insert(leaf2);

// Get tree information
let root = tree.get_root();
let depth = tree.get_depth();
let leaf_count = tree.get_leaf_count();

// Generate a proof
let proof = tree.generate_proof(0);
```

### In a Soroban Contract

```rust
use lean_imt::{LeanIMT, TREE_ROOT_KEY, TREE_DEPTH_KEY, TREE_LEAVES_KEY};

// Store tree state
let (leaves, depth, root) = tree.to_storage();
env.storage().instance().set(&TREE_LEAVES_KEY, &leaves);
env.storage().instance().set(&TREE_DEPTH_KEY, &depth);
env.storage().instance().set(&TREE_ROOT_KEY, &root);

// Restore tree state
let leaves: Vec<BytesN<32>> = env.storage().instance().get(&TREE_LEAVES_KEY)
    .unwrap_or(vec![&env]);
let depth: u32 = env.storage().instance().get(&TREE_DEPTH_KEY)
    .unwrap_or(0);
let root: BytesN<32> = env.storage().instance().get(&TREE_ROOT_KEY)
    .unwrap_or(BytesN::from_array(&env, &[0u8; 32]));

let tree = LeanIMT::from_storage(env.clone(), leaves, depth, root);
```

## API Reference

### Core Methods

- `new(env: Env) -> Self`: Create a new empty tree
- `insert(leaf: BytesN<32>)`: Insert a new leaf
- `get_root() -> BytesN<32>`: Get the current merkle root
- `get_depth() -> u32`: Get the current tree depth
- `get_leaf_count() -> u32`: Get the number of leaves
- `generate_proof(leaf_index: u32) -> Option<(Vec<BytesN<32>>, u32)>`: Generate inclusion proof

### Storage Methods

- `to_storage() -> (Vec<BytesN<32>>, u32, BytesN<32>)`: Serialize tree for storage
- `from_storage(env: Env, leaves: Vec<BytesN<32>>, depth: u32, root: BytesN<32>) -> Self`: Deserialize from storage

### Utility Methods

- `get_leaves() -> &Vec<BytesN<32>>`: Get reference to all leaves
- `is_empty() -> bool`: Check if tree is empty
- `get_leaf(index: usize) -> Option<&BytesN<32>>`: Get leaf at specific index

## Hash Function

The LeanIMT uses **Poseidon2** as its hash function, which provides:

- **Consistency**: Same hash function used in the contract and circuit
- **Security**: Cryptographically secure hash function
- **Efficiency**: Fast computation suitable for smart contracts
- **Standardization**: Widely adopted hash function in blockchain systems

The hash function is used to combine pairs of nodes when building the tree structure, ensuring the integrity and uniqueness of each merkle root.

## Compatibility with merkleProof.circom

The LeanIMT implementation is designed to be fully compatible with the `merkleProof.circom` circuit:

- **Proof Format**: The `generate_proof` method returns siblings and depth in the exact format expected by the circuit
- **Tree Structure**: The tree construction follows the same logic as the circuit
- **Hash Consistency**: Both use Poseidon for hashing, ensuring identical behavior

## Testing

Run the test suite:

```bash
cd lean-imt
cargo test
```

The tests cover:
- Tree creation and initialization
- Leaf insertion and tree growth
- Proof generation
- Storage serialization/deserialization
- Edge cases and error conditions

## Integration

This crate is designed to integrate with:

- **Privacy Pools Contract**: Stores commitments in the merkle tree
- **Zero-Knowledge Proofs**: Provides merkle proofs for circuit verification
- **Soroban Platform**: Native integration with Stellar's smart contract platform

## License

This project is part of the Soroban Privacy Pools implementation and follows the same licensing terms.
