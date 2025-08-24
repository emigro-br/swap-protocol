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
