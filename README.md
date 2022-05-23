![](cover.png)
Created by [@tinchoabbate](https://twitter.com/tinchoabbate)
Visit [damnvulnerabledefi.xyz](https://damnvulnerabledefi.xyz)

# Solutions
When contracts are used to solve challenges, they can be found under each ```contracts``` folder.
⠀
⠀
## 1) Unstoppable
### Catch - Hints
The issue in here is considering that the only way to send funds to the ```UnstoppableLender.sol``` contract is by executing the ```depositTokens``` (with a structure composed by a ```transferFrom``` method). There are many ways to make transactions that involve ERC20 tokens. Going from regular transactions to more creative ways such as selfdestructing contracts or predestinating funds!

### Solution
The ```flashLoan``` function seems fair but for one line. On ```line 40```, a local variable which state is updated on other function is vulnerable. We are speaking about ```poolBalance```, the weak point of this contract. It is only updated when the pool receives *DVT's* by calling the ```depositTokens```function. What happens if we send *DTV's* with a regular compliant ERC20 ```transfer```method? Or if we create a contract, deposit the *DVT's* and selfdestruct the contract towards the ```UnstoppableLender.sol``` contract? Exactly, the ```balanceOf(DVT's)``` inside the lending pool will be increased and this change won't be tracked by the poorly implemented ```poolBalance``` state.

By implementing this code on the ```Exploit``` part of the test, this level will be solved.

    this.token.connect(attacker).transfer(this.pool.address, 1);

### Learnings - Mitigations
- If we are checking a strict equality or inequality, analyze from where, who and when can manipulate each parts of the equation and evaluate if the malicious outcomes can be triggered. 
- This also is very common with ```require``` statements that are bypassed by tricking using a little bit of math and blockchain knowledge and also to unexpectedly enter ```if``` statements executions. 
- For equalities and inequalities, it is also advisable to think about feasible cases. For example, is it possible for a user to send a transaction with an amount greater than the current supply of Ether? But... is that possible for a 50% of supply? And 10%? What if the token in question is not Ether? All this border scenarios help understanding feasible cases! 

**Think outside the box before exploiters do!**
⠀
⠀
⠀
## 2) Naive Receiver
### Catch - Hints
This is an access control problem! What happens if I could go to the bank and borrow money on your behalf...? Also if it helps other approach can be, thinking about when it is convenient to define a variable as an absolute value and when it is more suitable to use relative values.

### Solution
The vulnerable point of this scheme is located at the function ```receiveEther()``` in the contract ```FlashLoanReceiver.sol```. It is important not only to check that the lending is coming from the desired pool but also checking that the trigger for the loan is done by the owner of the receiver contract. This is exploitable by asking for tokens to other borrower, on this case if we (as attackers) ask the pool for tokens to the receiver, because of the fee the balance on the latter will be drained (on this case after ten successful transactions). 
To execute this exploit running a simple script will do the job:

    let amountToLoan = ethers.utils.parseEther("0"); // This value can be anything (even zero) because the loan is effectively returned.
    let fixedFee = await this.pool.fixedFee();
    while ((await ethers.provider.getBalance(this.receiver.address)).gte(fixedFee)) {
        await this.pool.connect(attacker).flashLoan(this.receiver.address, amountToLoan);     
    }

### Learnings - Mitigations
- We need to track that the one who triggers the loan is the ```owner``` of the contract! Because we cannot control the code of the Lending Borrowing pool, we can only manage our own code. Sometimes the lending function of the pool passes the ```msg.sender``` as parameter that can be checked as an initiator within the security checks on the beginning of ```receiveEther()``` function. It can look something like this example, that uses the ```Ownable``` modifier:

        function triggerLoan(uint256 _amount) public onlyOwner{
            // Here is where the flash loan is asked
            lender.flashLoan(IERC3156FlashBorrower(this), _amount);
        }

        function onFlashLoan(
            address initiator,
            address token, 
            uint256 amount, 
            uint256, 
            bytes calldata data
            ) external override returns (bytes32){
                require(msg.sender == address(lender), "Not lending from the desired pool");
                require(initiator  == address(this), "Flashloan not requested by this contract");

                // Loan logic.


                // Finish Loan Logic - return the loan otherwise will fail
                return keccak256("ERC3156FlashBorrower.onFlashLoan");
            }

- We have to be extremely careful about the access control of each feature that involves funds. 

**Next time remember... when you lend money to a friend, never expect it back!**
⠀
⠀
⠀
## 3) Truster Lender Pool
### Catch - Hints
The best advice to solve this level is thinking about the word *trust*. Lets go back to the 90's. Would you give a blank check to Jordan Belfort? This level does the same. It is giving us a blank check...

### Solution
The vulnerability in here is on the ```line 36``` of the contract. The pool is giving us the chance to pick different actors as for ```borrower``` and ```target```. Also, the weakness is that by letting us input the ```calldata``` we can use it to exploit the pool by relying on one function of the ```ERC20``` standard. The exploit can be performed into two different ways. Performing one transaction and two. We will showcase the shorter version and explain how to do the other one.

Using the *blank check* that this contract gives us it is quite simple. We need to trigger the ```flashLoan``` function and pass it as ```calldata``` an instruction that let us transfer the tokens held on the ```TrusterLenderPool```. There is one function that let us do this only when a crucial requirement is fulfilled: the ```approval```. We will encode the ```approval``` call into the ```calldata```. The key in here is that this call is coming from the pool contract and thus will be valid (because technically, you can only approve the tokens held by you, otherwise this will be a mess...), in other words the call will be done by the ```msg.sender == address(pool)```. This will let either the ```attacker``` or the ```TrustCracker.sol``` contract to execute afterwards the ERC20 ```transferFrom``` function and drain the pool.

The basic structure to do so will be a function like this one (for interfaces initialization and how the contract should be deployed, you can check it under the ```contracts``` folder):

    function drainPool() public {
        uint256 poolBalance = token.balanceOf(address(pool));

        /* Beware with the function string under the encoder, if there are any spaces after the commas 
        the call will fail!
        */
        bytes memory payload = abi.encodeWithSignature("approve(address,uint256)", address(this), poolBalance);
        pool.flashLoan(0, attacker, address(token), payload);
        token.transferFrom(address(pool), attacker, poolBalance);
    }

This would be the shorter solution. To understand how this could be performed in a single txn lets see how flashloans are executed.
1) A receiver contract containing the ```receive``` function with the required structure by the pool, calls for the ```flashLoan```
2) Once the tokens arrive to the receiver, internal and desired transactions are performed (e.g. arbitrage).
3) When the internal transactions are finished, the receiver contract **must** send the tokens back to the pool.

The exploit can be done in a single transaction because the ```flashLoan``` function does not checks that the requested amount is **greater than zero**, this makes the *step 3* not required (because if I don't ask for tokens, I am not obliged to return anything!).  

The same exploit can be done while requesting tokens (more than zero), executing the ```approval``` for the pool balance, returning back the requested amount and in a former transaction call the ```transferFrom``` method and drain the ```TrusterLenderPool```.

### Learnings - Mitigations
- Respecting the ```flashloan``` basic contract structure is a must. 
- If the pool is only lending with the ```loan``` function, check that the requested amount is greater than zero. *Go elsewhere to ask for zero tokenz, we ar a sekur protokol pal.*
- Give a fixed calldata structure inside the ```loan``` function to prevent malicious calls. Do not request it as a parameter.
- To rely on logic, tokens can only be borrowed by contracts. Individual wallets cannot perform further logic such as contracts do.

**And remember, if a suited guy flexing cars and watches comes by offering huge APY's, run away. It is a scheme.**