// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./ISwapAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);
}

contract AerodromeAdapter is ISwapAdapter {
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

    // --- Pair-based ---

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        (bool stable, address factory) = abi.decode(data, (bool, address));
        require(factory != address(0), "Invalid factory address");

        emit SwapStarted("swapExactInput", tokenIn, tokenOut, amountIn, minAmountOut, recipient);

        require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, "Tokens not received");

        // Replace safeApprove with safeDecreaseAllowance and safeIncreaseAllowance
        uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(tokenIn).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(tokenIn).safeIncreaseAllowance(router, amountIn);

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route(tokenIn, tokenOut, stable, factory);

        try IAerodromeRouter(router).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            routes,
            recipient,
            block.timestamp + DEFAULT_DEADLINE
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
            emit SwapSuccess("swapExactInput", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory data) {
            string memory hexData = toHex(data);
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
        (bool stable, address factory) = abi.decode(data, (bool, address));
        require(factory != address(0), "Invalid factory address");

        emit SwapStarted("swapExactOutput", tokenIn, tokenOut, maxAmountIn, amountOut, recipient);

        require(IERC20(tokenIn).balanceOf(address(this)) >= maxAmountIn, "Tokens not received");

        // Replace safeApprove with safeDecreaseAllowance and safeIncreaseAllowance
        uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(tokenIn).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(tokenIn).safeIncreaseAllowance(router, maxAmountIn);

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route(tokenIn, tokenOut, stable, factory);

        try IAerodromeRouter(router).swapTokensForExactTokens(
            amountOut,
            maxAmountIn,
            routes,
            recipient,
            block.timestamp + DEFAULT_DEADLINE
        ) returns (uint256[] memory amounts) {
            amountInUsed = amounts[0];
            emit SwapSuccess("swapExactOutput", amountInUsed);
            if (amountInUsed < maxAmountIn) {
                SafeERC20.safeTransfer(IERC20(tokenIn), msg.sender, maxAmountIn - amountInUsed);
            }
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactOutput", reason);
            revert(string(abi.encodePacked("Swap failed: ", reason)));
        } catch (bytes memory data) {
            string memory hexData = toHex(data);
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
        (IAerodromeRouter.Route[] memory routes, uint256 deadline) = _decodeRouteData(path, data);

        emit SwapStarted("swapExactInputPath", path[0], path[path.length - 1], amountIn, minAmountOut, recipient);

        require(IERC20(path[0]).balanceOf(address(this)) >= amountIn, "Tokens not received");

        // Replace safeApprove with safeDecreaseAllowance and safeIncreaseAllowance
        uint256 currentAllowance = IERC20(path[0]).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(path[0]).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(path[0]).safeIncreaseAllowance(router, amountIn);

        try IAerodromeRouter(router).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            routes,
            recipient,
            deadline
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
            emit SwapSuccess("swapExactInputPath", amountOut);
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactInputPath", reason);
            revert(string(abi.encodePacked("Swap path failed: ", reason)));
        } catch (bytes memory data) {
            string memory hexData = toHex(data);
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
        (IAerodromeRouter.Route[] memory routes, uint256 deadline) = _decodeRouteData(path, data);

        emit SwapStarted("swapExactOutputPath", path[0], path[path.length - 1], maxAmountIn, amountOut, recipient);

        require(IERC20(path[0]).balanceOf(address(this)) >= maxAmountIn, "Tokens not received");

        // Replace safeApprove with safeDecreaseAllowance and safeIncreaseAllowance
        uint256 currentAllowance = IERC20(path[0]).allowance(address(this), router);
        if (currentAllowance > 0) {
            IERC20(path[0]).safeDecreaseAllowance(router, currentAllowance);
        }
        IERC20(path[0]).safeIncreaseAllowance(router, maxAmountIn);

        try IAerodromeRouter(router).swapTokensForExactTokens(
            amountOut,
            maxAmountIn,
            routes,
            recipient,
            deadline
        ) returns (uint256[] memory amounts) {
            amountInUsed = amounts[0];
            emit SwapSuccess("swapExactOutputPath", amountInUsed);
            if (amountInUsed < maxAmountIn) {
                SafeERC20.safeTransfer(IERC20(path[0]), msg.sender, maxAmountIn - amountInUsed);
            }
        } catch Error(string memory reason) {
            emit SwapFailed("swapExactOutputPath", reason);
            revert(string(abi.encodePacked("Swap path failed: ", reason)));
        } catch (bytes memory data) {
            string memory hexData = toHex(data);
            emit SwapFailed("swapExactOutputPath", hexData);
            revert(string(abi.encodePacked("Swap path failed: low-level error ", hexData)));
        }
    }

    // --- Route Decoding ---

    function _decodeRouteData(
        address[] calldata path,
        bytes memory data
    ) internal view returns (IAerodromeRouter.Route[] memory routes, uint256 deadline) {
        uint256 hopCount = path.length - 1;

        if (data.length >= hopCount * 64 + 32) {
            (bool[] memory stables, address[] memory factories, uint256 dl) =
                abi.decode(data, (bool[], address[], uint256));
            require(stables.length == hopCount && factories.length == hopCount, "Route data mismatch");

            routes = new IAerodromeRouter.Route[](hopCount);
            for (uint256 i = 0; i < hopCount; ++i) {
                routes[i] = IAerodromeRouter.Route(path[i], path[i + 1], stables[i], factories[i]);
            }
            deadline = dl;
        } else if (data.length == hopCount * 64) {
            (bool[] memory stables, address[] memory factories) = abi.decode(data, (bool[], address[]));
            require(stables.length == hopCount && factories.length == hopCount, "Route data mismatch");

            routes = new IAerodromeRouter.Route[](hopCount);
            for (uint256 i = 0; i < hopCount; ++i) {
                routes[i] = IAerodromeRouter.Route(path[i], path[i + 1], stables[i], factories[i]);
            }
            deadline = block.timestamp + DEFAULT_DEADLINE;
        } else {
            revert("Invalid route data");
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