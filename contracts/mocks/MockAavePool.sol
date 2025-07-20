// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

contract MockAavePool {
    address public aToken;
    
    function setATokenAddress(address asset, address aToken_) external {
        aToken = aToken_;
    }
    
    function getReserveData(address) external view returns (DataTypes.ReserveData memory data) {
        data.aTokenAddress = aToken;
    }
    
    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        // Prendre les tokens du caller
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        // Donner des aTokens
        IERC20(aToken).transfer(onBehalfOf, amount);
    }
    
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        IERC20(asset).transfer(to, amount);
        return amount;
    }
}