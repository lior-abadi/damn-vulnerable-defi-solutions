// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title FlashLoanReceiver
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract FlashLoanReceiver {
    using Address for address payable;

    address payable private pool;

    constructor(address payable poolAddress) {
        pool = poolAddress;
    }


    // Function called by the pool during flash loan
    function receiveEther(uint256 fee) public payable {
        require(msg.sender == pool, "Sender must be pool");

        uint256 amountToBeRepaid = msg.value + fee;
        console.log("------------------------------------");
        console.log("Balances ");
        require(address(this).balance >= amountToBeRepaid, "Cannot borrow that much");
        console.log("After borrowing:       ", address(this).balance / 10**18, "ETH");
        
        _executeActionDuringFlashLoan();
        
        // Return funds to pool
        pool.sendValue(amountToBeRepaid);
        console.log("Before paying back:    ", address(this).balance / 10**18, "ETH");
        console.log(" ");
    }

    // Internal function where the funds received are used
    function _executeActionDuringFlashLoan() internal {    
        
    }

    // Allow deposits of ETH
    receive () external payable {}
}