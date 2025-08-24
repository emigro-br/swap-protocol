// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./ISwapAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

contract UniswapV3Adapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    IV3SwapRouter public immutable router;
    uint256 public constant DEFAULT_DEADLINE = 300;

    event SwapStarted(string method, address tokenIn, address tokenOut, uint256 amount, uint256 minOrMax, address recipient);
    event SwapSuccess(string method, uint256 amountUsedOrOut);
    event SwapFailed(string method, string reason);

    constructor(address _router) {
        require(_router != address(0), "Invalid router");
        router = IV3SwapRouter(_router);
    }

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        uint24 fee = abi.decode(data, (uint24));

        emit SwapStarted("swapExactInput", tokenIn, tokenOut, amountIn, minAmountOut, recipient);

        require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, "Tokens not received");

        uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), address(router));
        if (currentAllowance > 0) {
            IERC20(tokenIn).safeDecreaseAllowance(address(router), currentAllowance);
        }
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);

        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        try router.exactInputSingle(params) returns (uint256 result) {
            amountOut = result;
            emit SwapSuccess("swapExactInput", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            string memory hexData = toHex(lowLevelData);
            emit SwapFailed("swapExactInput", hexData);
            revert(string(abi.encodePacked("Swap failed: low-level error ", hexData)));
        }
    }

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 maxAmountIn,
        uint256 amountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountInUsed) {
        uint24 fee = abi.decode(data, (uint24));

        emit SwapStarted("swapExactOutput", tokenIn, tokenOut, maxAmountIn, amountOut, recipient);

        require(IERC20(tokenIn).balanceOf(address(this)) >= maxAmountIn, "Tokens not received");

        uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), address(router));
        if (currentAllowance > 0) {
            IERC20(tokenIn).safeDecreaseAllowance(address(router), currentAllowance);
        }
        IERC20(tokenIn).safeIncreaseAllowance(address(router), maxAmountIn);

        IV3SwapRouter.ExactOutputSingleParams memory params = IV3SwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: recipient,
            amountOut: amountOut,
            amountInMaximum: maxAmountIn,
            sqrtPriceLimitX96: 0
        });

        try router.exactOutputSingle(params) returns (uint256 result) {
            amountInUsed = result;
            emit SwapSuccess("swapExactOutput", amountInUsed);
            if (amountInUsed < maxAmountIn) {
                IERC20(tokenIn).safeTransfer(msg.sender, maxAmountIn - amountInUsed);
            }
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactOutput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            string memory hexData = toHex(lowLevelData);
            emit SwapFailed("swapExactOutput", hexData);
            revert(string(abi.encodePacked("Swap failed: low-level error ", hexData)));
        }
    }

    function swapExactInputPath(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        (uint24[] memory fees, uint256 deadline) = _decodePathData(data);
        require(path.length == fees.length + 1, "Path/fees mismatch");

        emit SwapStarted("swapExactInputPath", path[0], path[path.length - 1], amountIn, minAmountOut, recipient);

        require(IERC20(path[0]).balanceOf(address(this)) >= amountIn, "Tokens not received");

        uint256 currentAllowance = IERC20(path[0]).allowance(address(this), address(router));
        if (currentAllowance > 0) {
            IERC20(path[0]).safeDecreaseAllowance(address(router), currentAllowance);
        }
        IERC20(path[0]).safeIncreaseAllowance(address(router), amountIn);

        bytes memory encodedPath = _encodePath(path, fees);

        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: encodedPath,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        try router.exactInput(params) returns (uint256 result) {
            amountOut = result;
            emit SwapSuccess("swapExactInputPath", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInputPath", reason);
            revert(string(abi.encodePacked("Swap path failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            emit SwapFailed("swapExactInputPath", toHex(lowLevelData));
            revert(string(abi.encodePacked("Swap path failed: low-level error ", toHex(lowLevelData))));
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

    (uint24[] memory fees, uint256 deadline) = _decodePathData(data);
    require(path.length == fees.length + 1, "Path/fees mismatch");

    bytes memory encodedPath = _encodePathReverse(path, fees);

    IERC20 inputToken = IERC20(path[0]);
    uint256 allowance = inputToken.allowance(address(this), address(router));
    if (allowance > 0) {
        inputToken.safeDecreaseAllowance(address(router), allowance);
    }
    inputToken.safeIncreaseAllowance(address(router), maxAmountIn);

    IV3SwapRouter.ExactOutputParams memory params = IV3SwapRouter.ExactOutputParams({
        path: encodedPath,
        recipient: recipient,
        amountOut: amountOut,
        amountInMaximum: maxAmountIn
    });

    try router.exactOutput(params) returns (uint256 result) {
        amountInUsed = result;
        emit SwapSuccess("swapExactOutputPath", amountInUsed);
        if (amountInUsed < maxAmountIn) {
            inputToken.safeTransfer(msg.sender, maxAmountIn - amountInUsed);
        }
    } catch Error(string memory reason) {
        emit SwapFailed("swapExactOutputPath", reason);
        revert(string(abi.encodePacked("Swap path failed: ", reason)));
    } catch (bytes memory lowLevelData) {
        emit SwapFailed("swapExactOutputPath", toHex(lowLevelData));
        revert(string(abi.encodePacked("Swap path failed: low-level error ", toHex(lowLevelData))));
    }
}


    function _decodePathData(bytes memory data) internal view returns (uint24[] memory fees, uint256 deadline) {
        if (data.length >= 96) {
            (fees, deadline) = abi.decode(data, (uint24[], uint256));
        } else if (data.length >= 32) {
            fees = abi.decode(data, (uint24[]));
            deadline = block.timestamp + DEFAULT_DEADLINE;
        } else {
            revert("Invalid adapter data");
        }
    }

    function _encodePath(address[] memory path, uint24[] memory fees) internal pure returns (bytes memory result) {
        for (uint256 i = 0; i < fees.length; i++) {
            result = bytes.concat(result, abi.encodePacked(path[i], fees[i]));
        }
        result = bytes.concat(result, abi.encodePacked(path[path.length - 1]));
    }

    function _encodePathReverse(address[] memory path, uint24[] memory fees) internal pure returns (bytes memory result) {
        result = abi.encodePacked(path[path.length - 1]);
        for (uint256 i = fees.length; i > 0; i--) {
            result = bytes.concat(result, abi.encodePacked(fees[i - 1], path[i - 1]));
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
