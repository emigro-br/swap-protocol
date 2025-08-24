// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./ISwapAdapter.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EmigroRouter is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    mapping(bytes32 => address) public adapterForPath;
    mapping(address => bool) public feeExempt;
    mapping(address => bool) public approvedAdapters;

    uint256 public defaultDeadline;
    uint256 public feeBps;
    address public feeReceiver;

    event SwapPerformed(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed adapter,
        address recipient
    );
    event RefundIssued(address indexed token, address indexed user, uint256 amount);
    event EmergencyWithdrawETH(address indexed to, uint256 amount);
    event EmergencyWithdrawToken(address indexed token, address indexed to, uint256 amount);
    event FeeUpdated(uint256 newFeeBps);
    event FeeReceiverUpdated(address newReceiver);
    event FeeExemptSet(address indexed wallet, bool isExempt);
    event AdapterWhitelisted(address adapter, bool approved);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        defaultDeadline = 300;
        feeBps = 50;
        feeReceiver = 0x3543653A29F9Dc92188c2a68A1e847f8E21f9772;

        approvedAdapters[0x1b9042f6e862E20bb653f5C1EAd8AB679eE73FAB] = true;
        approvedAdapters[0x4fBAA929d8eB386fABd1144c88F2Fd63A39379EA] = true;
        approvedAdapters[0x1a9b2b13e4d70c78406C55A6aa27c6bd9B962470] = true;
    }

    function setAdapterApproval(address adapter, bool approved) external onlyOwner {
        require(adapter != address(0), "Zero address");
        approvedAdapters[adapter] = approved;
        emit AdapterWhitelisted(adapter, approved);
    }

    function setDefaultDeadline(uint256 seconds_) external onlyOwner {
        defaultDeadline = seconds_;
    }

    function updateFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "Fee too high");
        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    function updateFeeReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Zero address");
        feeReceiver = newReceiver;
        emit FeeReceiverUpdated(newReceiver);
    }

    function setFeeExempt(address wallet, bool exempt) external onlyOwner {
        feeExempt[wallet] = exempt;
        emit FeeExemptSet(wallet, exempt);
    }

    function _chargeFee(address token, address from, uint256 amount) internal returns (uint256 netAmount) {
        if (feeBps == 0 || feeExempt[from]) {
            return amount;
        }
        uint256 fee = (amount * feeBps) / 10000;
        netAmount = amount - fee;
        if (fee > 0) {
            IERC20(token).safeTransferFrom(from, feeReceiver, fee);
        }
    }

    function _validateAdapter(address adapter) internal view {
        require(adapter != address(0), "Invalid adapter");
        require(approvedAdapters[adapter], "Adapter not approved");
    }

    function swapExactInputVia(
        address adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external payable nonReentrant returns (uint256 amountOut) {
        _validateAdapter(adapter);
        uint256 netAmount = _chargeFee(tokenIn, msg.sender, amountIn);
        _handleTransfer(tokenIn, adapter, netAmount);

        amountOut = ISwapAdapter(adapter).swapExactInput(tokenIn, tokenOut, netAmount, minAmountOut, recipient, data);
        emit SwapPerformed(tokenIn, tokenOut, netAmount, amountOut, adapter, recipient);
    }

    function swapExactOutputVia(
        address adapter,
        address tokenIn,
        address tokenOut,
        uint256 maxAmountIn,
        uint256 amountOut,
        address recipient,
        bytes calldata data
    ) external payable nonReentrant returns (uint256 amountInUsed) {
        _validateAdapter(adapter);
        uint256 netAmount = _chargeFee(tokenIn, msg.sender, maxAmountIn);
        _handleTransfer(tokenIn, adapter, netAmount);

        amountInUsed = ISwapAdapter(adapter).swapExactOutput(tokenIn, tokenOut, netAmount, amountOut, recipient, data);
        emit SwapPerformed(tokenIn, tokenOut, amountInUsed, amountOut, adapter, recipient);
    }

    function _handleTransfer(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH sent");
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, to, amount);
        }
    }

    function emergencyWithdrawETH(address to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = to.call{value: balance}("");
        require(success, "ETH transfer failed");
        emit EmergencyWithdrawETH(to, balance);
    }

    function emergencyWithdrawToken(address token, address to) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No token balance");
        IERC20(token).safeTransfer(to, balance);
        emit EmergencyWithdrawToken(token, to, balance);
    }

    receive() external payable {}
}
