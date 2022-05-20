![](cover.png)
Created by [@tinchoabbate](https://twitter.com/tinchoabbate)
Visit [damnvulnerabledefi.xyz](https://damnvulnerabledefi.xyz)

# Solutions

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

