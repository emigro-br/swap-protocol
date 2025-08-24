// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./ISwapAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);
}

contract UniswapV2Adapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    address public immutable router;
    uint256 public constant DEFAULT_DEADLINE = 300;

    event SwapStarted(string method, address tokenIn, address tokenOut, uint256 amount, uint256 minOrMax, address recipient);
    event SwapSuccess(string method, uint256 amountUsedOrOut);
    event SwapFailed(string method, string reason);

    constructor(address _router) {
        require(_router != address(0), "Invalid router address");
        router = _router;
    }

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata /* data */
    ) external override returns (uint256 amountOut) {
        emit SwapStarted("swapExactInput", tokenIn, tokenOut, amountIn, minAmountOut, recipient);
        require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, "Tokens not received");

        uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(tokenIn).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(tokenIn).safeIncreaseAllowance(router, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try IUniswapV2Router(router).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            recipient,
            block.timestamp + DEFAULT_DEADLINE
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
            emit SwapSuccess("swapExactInput", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory data) {
            emit SwapFailed("swapExactInput", toHex(data));
            revert(string(abi.encodePacked("Swap failed: low-level error ", toHex(data))));
        }
    }

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 maxAmountIn,
        uint256 amountOut,
        address recipient,
        bytes calldata /* data */
    ) external override returns (uint256 amountInUsed) {
        emit SwapStarted("swapExactOutput", tokenIn, tokenOut, maxAmountIn, amountOut, recipient);
        require(IERC20(tokenIn).balanceOf(address(this)) >= maxAmountIn, "Tokens not received");

        uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(tokenIn).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(tokenIn).safeIncreaseAllowance(router, maxAmountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try IUniswapV2Router(router).swapTokensForExactTokens(
            amountOut,
            maxAmountIn,
            path,
            recipient,
            block.timestamp + DEFAULT_DEADLINE
        ) returns (uint256[] memory amounts) {
            amountInUsed = amounts[0];
            emit SwapSuccess("swapExactOutput", amountInUsed);
            if (amountInUsed < maxAmountIn) {
                IERC20(tokenIn).safeTransfer(msg.sender, maxAmountIn - amountInUsed);
            }
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactOutput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory data) {
            emit SwapFailed("swapExactOutput", toHex(data));
            revert(string(abi.encodePacked("Swap failed: low-level error ", toHex(data))));
        }
    }

    function swapExactInputPath(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        emit SwapStarted("swapExactInputPath", path[0], path[path.length - 1], amountIn, minAmountOut, recipient);
        require(path.length >= 2, "Invalid path");
        require(IERC20(path[0]).balanceOf(address(this)) >= amountIn, "Tokens not received");

        uint256 currentAllowance = IERC20(path[0]).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(path[0]).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(path[0]).safeIncreaseAllowance(router, amountIn);

        uint256 deadline = _decodeDeadline(data);

        try IUniswapV2Router(router).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            recipient,
            deadline
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
            emit SwapSuccess("swapExactInputPath", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInputPath", reason);
            revert(string(abi.encodePacked("Swap path failed: ", reason)));
        } catch (bytes memory data) {
            emit SwapFailed("swapExactInputPath", toHex(data));
            revert(string(abi.encodePacked("Swap path failed: low-level error ", toHex(data))));
        }
    }

    function swapExactOutputPath(
        address[] calldata path,
        uint256 maxAmountIn,
        uint256 amountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountInUsed) {
        emit SwapStarted("swapExactOutputPath", path[0], path[path.length - 1], maxAmountIn, amountOut, recipient);
        require(path.length >= 2, "Invalid path");
        require(IERC20(path[0]).balanceOf(address(this)) >= maxAmountIn, "Tokens not received");

        uint256 currentAllowance = IERC20(path[0]).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(path[0]).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(path[0]).safeIncreaseAllowance(router, maxAmountIn);

        uint256 deadline = _decodeDeadline(data);

        try IUniswapV2Router(router).swapTokensForExactTokens(
            amountOut,
            maxAmountIn,
            path,
            recipient,
            deadline
        ) returns (uint256[] memory amounts) {
            amountInUsed = amounts[0];
            emit SwapSuccess("swapExactOutputPath", amountInUsed);
            if (amountInUsed < maxAmountIn) {
                IERC20(path[0]).safeTransfer(msg.sender, maxAmountIn - amountInUsed);
            }
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactOutputPath", reason);
            revert(string(abi.encodePacked("Swap path failed: ", reason)));
        } catch (bytes memory data) {
            emit SwapFailed("swapExactOutputPath", toHex(data));
            revert(string(abi.encodePacked("Swap path failed: low-level error ", toHex(data))));
        }
    }

    function _decodeDeadline(bytes memory data) internal view returns (uint256 deadline) {
        if (data.length == 32) {
            deadline = abi.decode(data, (uint256));
        } else {
            deadline = block.timestamp + DEFAULT_DEADLINE;
        }
    }

    function toHex(bytes memory data) internal pure returns (string memory) {
        bytes16 hexChars = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = hexChars[uint8(data[i] >> 4)];
            str[3 + i * 2] = hexChars[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}