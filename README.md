# Infernet SDK

[![Tests](https://github.com/ritual-net/infernet-sdk/actions/workflows/test_contracts.yml/badge.svg)](https://github.com/ritual-net/infernet-sdk/actions/workflows/test_contracts.yml)

The Infernet SDK is a set of smart contracts from [Ritual](https://ritual.net) that enable on-chain smart contracts to subscribe to off-chain compute workloads.

Developers can inherit one of two simple interfaces, [`CallbackConsumer`](./src/consumer/Callback.sol) or [`SubscriptionConsumer`](./src/consumer/Subscription.sol) in their smart contracts, and consume one-time or recurring computation.

> [!IMPORTANT]
> Smart contract architecture, quick-start guides, and in-depth documentation can be found on the [Ritual documentation website](https://docs.ritual.net/infernet/sdk/architecture)

> [!WARNING]
> These smart contracts are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the smart contracts.

## Local deployment and usage

First, ensure you have [Foundry installed locally](https://book.getfoundry.sh/getting-started/installation). A simple way to install is to run the following command:

```bash
# Install foundryup, follow instructions
curl -L https://foundry.paradigm.xyz | bash
```

### Building and running

To build, run, or execute other commands, you can reference the [Makefile](./Makefile).

The default target (`make`) will:

1. Install all dependencies
2. Clean existing build outputs
3. Format code
4. Build code and copy compiled artifacts
5. Run test suite

### Using within your own contracts

To import Infernet as a library, you can install the code in your repo with [forge](https://book.getfoundry.sh/forge/):

```bash
forge install https://github.com/ritual-net/infernet-sdk
```

To integrate with the contracts, the available interfaces can be imported from [./src/consumer](./src/consumer/):

```solidity
import {CallbackConsumer} from "infernet/consumer/Callback.sol";

contract MyContract is CallbackConsumer {
   function requestSomeComputeResponse() {
      // This will create a new one-time callback request for off-chain compute
      _requestCompute(...);
   }

   function _receiveCompute(...) internal override {
      // Here you will receive the off-chain compute response
   }
}
```

```solidity
import {SubscriptionConsumer} from "infernet/consumer/Subscription.sol";

contract MyContract is SubscriptionConsumer {
   function scheduleComputeResponse() {
      // This will create a new recurring request for off-chain compute
      _createComputeSubscription(...);
   }

   function cancelScheduledComputeResponse() {
      // This will allow you to cancel scheduled requests
      _cancelComputeSubscription(...);
   }

   function _receiveCompute(...) internal override {
      // Here you will receive the off-chain compute output
   }
}
```

## Repository structure

```bash
.
├── .env.sample # Sample env variables
├── .gas-snapshot # Function execution gas snapshot
├── Makefile
├── README.md
├── STYLE.md
├── compiled # Pre-compiled artifacts (via solc)
│   └── Verifier.sol
│       ├── Halo2Verifier.json
│       └── Verifier.sol
├── foundry.toml # Foundry setup
├── remappings.txt
├── scripts
│   └── Deploy.sol # EIP712Coordinator deploy script
├── src # Contracts
│   ├── Coordinator.sol # Base coordinator
│   ├── EIP712Coordinator.sol # EIP-712 typed message supporting coordinator
│   ├── Manager.sol # Node manager
│   ├── consumer # Consumers inherited by developers
│   │   ├── Base.sol
│   │   ├── Callback.sol # CallbackConsumer
│   │   └── Subscription.sol # SubscriptionConsumer
│   └── pattern # Useful developer patterns
│       └── Delegator.sol # EIP-712 delegator
└── test # Tests
    ├── Coordinator.t.sol
    ├── E2E.t.sol
    ├── EIP712Coordinator.t.sol
    ├── Manager.t.sol
    ├── ezkl # E2E tests w/ EZKL-generated proofs
    │   ├── BalanceScale.sol
    │   └── DataAttestor.sol
    ├── lib # Useful libraries
    │   ├── LibSign.sol # EIP-712 signing
    │   └── LibStruct.sol # Struct parsing
    └── mocks
        ├── MockManager.sol
        ├── MockNode.sol # Mock Infernet node
        └── consumer
            ├── Base.sol
            ├── Callback.sol
            ├── DelegatorCallback.sol
            └── Subscription.sol
```

## License

[BSD 3-clause Clear](./LICENSE)
