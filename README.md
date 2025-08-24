  # Emigro Swap Protocol

  **A decentralized, upgradeable swap router for EVM-compatible blockchains**  
  Seamless token swaps with native smart wallet support (Circle, Account Abstraction, and beyond).

  ---

  ## Overview

  The **Emigro Protocol** is a decentralized swap router designed to facilitate efficient token swaps across multiple decentralized exchanges (DEXes) on EVM-compatible blockchains.

  - Unified entry point for developers and users  
  - Upgradeable proxy design for future enhancements  
  - Adapters for Uniswap V2, Uniswap V3, Aerodrome (V2-style), and Slipstream (V3-style)  
  - Smart wallet–first architecture, built with account abstraction (AA) and Circle Programmable Wallets in mind

  ---

  ## Key Features

  - Multi-DEX support: Uniswap V2/V3, Aerodrome, Slipstream  
  - Swap types: Exact input/output, single-pair, and upcoming multi-hop  
  - Fee mechanism: Default 0.5% fee, configurable and exemptable  
  - Security: Reentrancy guards, whitelisted adapters, emergency withdraw  
  - Upgradeability: Built with OpenZeppelin’s upgradeable proxy  
  - Smart wallet ready: Native support for Circle and AA wallets

  ---

  ## How It Works

  **Flow:**
User → EmigroRouter (fee & validation) → Adapter → DEX → Recipient

yaml
Copy
Edit

- Router Contract: Handles validation, fees, and execution  
- Adapters: Protocol-specific bridges to underlying DEXes  
- EOAs + Smart Wallets: Works seamlessly with both

---

## Why Emigro?

Unlike traditional routers (Uniswap, 1inch, 0x), **Emigro** is designed from the ground up for smart contract wallets:

- One-call swaps (no approval bundling)  
- Gas-optimized for AA wallets  
- Proxy upgradeable for continuous improvements  
- Simpler integrations — no offchain quote APIs needed

---

## Competitive Landscape

| Feature                   | Emigro Protocol | 1inch      | Uniswap Universal Router | 0x Protocol |
|----------------------------|-----------------|------------|--------------------------|-------------|
| Smart Wallet Compatibility | Excellent       | Good       | Moderate                 | Moderate    |
| Multi-DEX Aggregation      | Uniswap + Aerodrome + Slipstream | 100+ sources | Uniswap only | 100+ sources |
| Onchain Execution          | Direct calls    | Via aggregator | Direct Uniswap           | Offchain fills |
| Fees                       | 0.5% (exemptable) | Variable   | None                     | Maker/taker |
| Upgradeability             | Proxy           | Immutable  | Immutable                 | API-based   |

---

# Usage Examples

## Solidity (Read Router State)

```solidity
address router = 0x6b0e33f464dD297cf997DfA96D694aFC153e7F6F;

uint256 feeBps = IEmigroRouter(router).feeBps();
address feeReceiver = IEmigroRouter(router).feeReceiver();
```

## JavaScript (Exact Input Swap via ethers.js)

```javascript
const router = new ethers.Contract(
  routerAddr,
  ['function swapExactInputVia(address,address,address,uint256,uint256,address,bytes) returns (uint256)'],
  wallet
);

await erc20.approve(routerAddr, amountIn);

const tx = await router.swapExactInputVia(
  slipstreamAdapter,
  eurc,
  usdc,
  amountIn,
  minOut,
  wallet.address,
  data
);
```

---

# Installation (Development)

```bash
git clone https://github.com/emigro-br/swap-protocol.git
cd swap-protocol
npm install
```

## Compile contracts

```bash
npx hardhat compile
```

## Run tests

```bash
npx hardhat test
```

---

# Project Structure

```bash
contracts/      # Solidity smart contracts
adapters/       # Protocol adapters (Uniswap, Aerodrome, Slipstream)
scripts/        # Local scripts (ignored in repo)
test/           # Hardhat test suite
```

---

# Security

- Contracts include reentrancy protection  
- Adapters are whitelisted by the protocol owner  
- Emergency withdrawal functions are available  

> **Note:** The protocol is under active development. Use in production at your own risk until an external audit is complete.
