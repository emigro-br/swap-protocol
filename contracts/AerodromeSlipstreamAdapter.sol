// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./ISwapAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISlipstreamFactory {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

interface ISlipstreamRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}

contract AerodromeSlipstreamAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    address public immutable router;
    address public immutable factory;
    uint256 public constant DEFAULT_DEADLINE = 300;

    event SwapStarted(string method, address tokenIn, address tokenOut, uint256 amount, uint256 minOrMax, address recipient);
    event SwapSuccess(string method, uint256 amountUsedOrOut);
    event SwapFailed(string method, string reason);

    constructor(address _router, address _factory) {
        require(_router != address(0), "Invalid router address");
        require(_factory != address(0), "Invalid factory address");
        router = _router;
        factory = _factory;
    }

    // --- Pair-based ---

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        int24 tickSpacing = abi.decode(data, (int24));
        require(tickSpacing > 0, "Invalid tick spacing");

        emit SwapStarted("swapExactInput", tokenIn, tokenOut, amountIn, minAmountOut, recipient);

        require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, "Tokens not received");

        // Manage approvals
        _approveToken(tokenIn, amountIn);

        ISlipstreamRouter.ExactInputSingleParams memory params = ISlipstreamRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            tickSpacing: tickSpacing,
            recipient: recipient,
            deadline: block.timestamp + DEFAULT_DEADLINE,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        try ISlipstreamRouter(router).exactInputSingle(params) returns (uint256 result) {
            amountOut = result;
            emit SwapSuccess("swapExactInput", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            string memory hexData = _toHex(lowLevelData);
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
        int24 tickSpacing = abi.decode(data, (int24));
        require(tickSpacing > 0, "Invalid tick spacing");

        emit SwapStarted("swapExactOutput", tokenIn, tokenOut, maxAmountIn, amountOut, recipient);

        require(IERC20(tokenIn).balanceOf(address(this)) >= maxAmountIn, "Tokens not received");

        // Manage approvals
        _approveToken(tokenIn, maxAmountIn);

        ISlipstreamRouter.ExactOutputSingleParams memory params = ISlipstreamRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            tickSpacing: tickSpacing,
            recipient: recipient,
            deadline: block.timestamp + DEFAULT_DEADLINE,
            amountOut: amountOut,
            amountInMaximum: maxAmountIn,
            sqrtPriceLimitX96: 0
        });

        try ISlipstreamRouter(router).exactOutputSingle(params) returns (uint256 result) {
            amountInUsed = result;
            emit SwapSuccess("swapExactOutput", amountInUsed);
            if (amountInUsed < maxAmountIn) {
                SafeERC20.safeTransfer(IERC20(tokenIn), msg.sender, maxAmountIn - amountInUsed);
            }
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactOutput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            string memory hexData = _toHex(lowLevelData);
            emit SwapFailed("swapExactOutput", hexData);
            revert(string(abi.encodePacked("Swap failed: low-level error ", hexData)));
        }
    }

    // --- Path-based ---

    function swapExactInputPath(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        (int24[] memory tickSpacings, uint256 deadline) = _decodePathData(path, data);
        bytes memory encodedPath = _encodePath(path, tickSpacings);

        emit SwapStarted("swapExactInputPath", path[0], path[path.length - 1], amountIn, minAmountOut, recipient);

        require(IERC20(path[0]).balanceOf(address(this)) >= amountIn, "Tokens not received");

        // Manage approvals
        _approveToken(path[0], amountIn);

        ISlipstreamRouter.ExactInputParams memory params = ISlipstreamRouter.ExactInputParams({
            path: encodedPath,
            recipient: recipient,
            deadline: deadline == 0 ? block.timestamp + DEFAULT_DEADLINE : deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        try ISlipstreamRouter(router).exactInput(params) returns (uint256 result) {
            amountOut = result;
            emit SwapSuccess("swapExactInputPath", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInputPath", reason);
            revert(string(abi.encodePacked("Swap path failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            string memory hexData = _toHex(lowLevelData);
            emit SwapFailed("swapExactInputPath", hexData);
            revert(string(abi.encodePacked("Swap path failed: low-level error ", hexData)));
        }
    }

    function swapExactOutputPath(
        address[] calldata path,
        uint256 maxAmountIn,
        uint256 amountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountInUsed) {
        (int24[] memory tickSpacings, uint256 deadline) = _decodePathData(path, data);
        bytes memory encodedPath = _encodePathReverse(path, tickSpacings);

        emit SwapStarted("swapExactOutputPath", path[0], path[path.length - 1], maxAmountIn, amountOut, recipient);

        require(IERC20(path[0]).balanceOf(address(this)) >= maxAmountIn, "Tokens not received");

        // Manage approvals
        _approveToken(path[0], maxAmountIn);

        ISlipstreamRouter.ExactOutputParams memory params = ISlipstreamRouter.ExactOutputParams({
            path: encodedPath,
            recipient: recipient,
            deadline: deadline == 0 ? block.timestamp + DEFAULT_DEADLINE : deadline,
            amountOut: amountOut,
            amountInMaximum: maxAmountIn
        });

        try ISlipstreamRouter(router).exactOutput(params) returns (uint256 result) {
            amountInUsed = result;
            emit SwapSuccess("swapExactOutputPath", amountInUsed);
            if (amountInUsed < maxAmountIn) {
                SafeERC20.safeTransfer(IERC20(path[0]), msg.sender, maxAmountIn - amountInUsed);
            }
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactOutputPath", reason);
            revert(string(abi.encodePacked("Swap path failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            string memory hexData = _toHex(lowLevelData);
            emit SwapFailed("swapExactOutputPath", hexData);
            revert(string(abi.encodePacked("Swap path failed: low-level error ", hexData)));
        }
    }

    // --- Internal Functions ---

    function _approveToken(address token, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(token).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(token).safeIncreaseAllowance(router, amount);
    }

    function _decodePathData(
        address[] calldata path,
        bytes memory data
    ) internal pure returns (int24[] memory tickSpacings, uint256 deadline) {
        uint256 hopCount = path.length - 1;
        if (data.length >= hopCount * 32 + 32) {
            (tickSpacings, deadline) = abi.decode(data, (int24[], uint256));
            require(tickSpacings.length == hopCount, "Tick spacings mismatch");
        } else if (data.length == hopCount * 32) {
            tickSpacings = abi.decode(data, (int24[]));
            require(tickSpacings.length == hopCount, "Tick spacings mismatch");
            deadline = 0;
        } else {
            revert("Invalid path data");
        }
        for (uint256 i = 0; i < tickSpacings.length; i++) {
            require(tickSpacings[i] > 0, "Invalid tick spacing");
        }
    }

    function _encodePath(address[] calldata path, int24[] memory tickSpacings) internal pure returns (bytes memory) {
        bytes memory encodedPath;
        for (uint256 i = 0; i < path.length - 1; i++) {
            encodedPath = abi.encodePacked(encodedPath, path[i], tickSpacings[i], path[i + 1]);
        }
        return encodedPath;
    }

    function _encodePathReverse(address[] calldata path, int24[] memory tickSpacings) internal pure returns (bytes memory) {
        bytes memory encodedPath;
        for (uint256 i = path.length - 1; i > 0; i--) {
            encodedPath = abi.encodePacked(encodedPath, path[i], tickSpacings[i - 1], path[i - 1]);
        }
        return encodedPath;
    }

    function _toHex(bytes memory data) internal pure returns (string memory) {
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