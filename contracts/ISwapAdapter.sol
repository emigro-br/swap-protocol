// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ISwapAdapter {
    // Pair-based exact input swap
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external returns (uint256 amountOut);

    // Pair-based exact output swap
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 maxAmountIn,
        uint256 amountOut,
        address recipient,
        bytes calldata data
    ) external returns (uint256 amountInUsed);

    // Path-based exact input swap (e.g., tokenA -> tokenB -> tokenC)
    function swapExactInputPath(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external returns (uint256 amountOut);

    // Path-based exact output swap (e.g., tokenA -> tokenB -> tokenC)
    function swapExactOutputPath(
        address[] calldata path,
        uint256 maxAmountIn,
        uint256 amountOut,
        address recipient,
        bytes calldata data
    ) external returns (uint256 amountInUsed);
}
