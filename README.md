![](cover.png)
Created by [@tinchoabbate](https://twitter.com/tinchoabbate)
Visit [damnvulnerabledefi.xyz](https://damnvulnerabledefi.xyz)

# Solutions

When contracts are used to solve challenges, they can be found under each `contracts` folder.
⠀
⠀

## 1) Unstoppable

### Catch - Hints

The issue in here is considering that the only way to send funds to the `UnstoppableLender.sol` contract is by executing the `depositTokens` (with a structure composed by a `transferFrom` method). There are many ways to make transactions that involve ERC20 tokens. Going from regular transactions to more creative ways such as selfdestructing contracts or predestinating funds!

### Solution

The `flashLoan` function seems fair but for one line. On `line 40`, a local variable which state is updated on other function is vulnerable. We are speaking about `poolBalance`, the weak point of this contract. It is only updated when the pool receives _DVT's_ by calling the `depositTokens`function. What happens if we send _DTV's_ with a regular compliant ERC20 `transfer`method? Or if we create a contract, deposit the _DVT's_ and selfdestruct the contract towards the `UnstoppableLender.sol` contract? Exactly, the `balanceOf(DVT's)` inside the lending pool will be increased and this change won't be tracked by the poorly implemented `poolBalance` state.

By implementing this code on the `Exploit` part of the test, this level will be solved.

    this.token.connect(attacker).transfer(this.pool.address, 1);

### Learnings - Mitigations

- If we are checking a strict equality or inequality, analyze from where, who and when can manipulate each parts of the equation and evaluate if the malicious outcomes can be triggered.
- This also is very common with `require` statements that are bypassed by tricking using a little bit of math and blockchain knowledge and also to unexpectedly enter `if` statements executions.
- For equalities and inequalities, it is also advisable to think about feasible cases. For example, is it possible for a user to send a transaction with an amount greater than the current supply of Ether? But... is that possible for a 50% of supply? And 10%? What if the token in question is not Ether? All this border scenarios help understanding feasible cases!

**Think outside the box before exploiters do!**
⠀
⠀
⠀

## 2) Naive Receiver

### Catch - Hints

This is an access control problem! What happens if I could go to the bank and borrow money on your behalf...? Also if it helps other approach can be, thinking about when it is convenient to define a variable as an absolute value and when it is more suitable to use relative values.

### Solution

The vulnerable point of this scheme is located at the function `receiveEther()` in the contract `FlashLoanReceiver.sol`. It is important not only to check that the lending is coming from the desired pool but also checking that the trigger for the loan is done by the owner of the receiver contract. This is exploitable by asking for tokens to other borrower, on this case if we (as attackers) ask the pool for tokens to the receiver, because of the fee the balance on the latter will be drained (on this case after ten successful transactions).
To execute this exploit running a simple script will do the job:

    let amountToLoan = ethers.utils.parseEther("0"); // This value can be anything (even zero) because the loan is effectively returned.
    let fixedFee = await this.pool.fixedFee();
    while ((await ethers.provider.getBalance(this.receiver.address)).gte(fixedFee)) {
        await this.pool.connect(attacker).flashLoan(this.receiver.address, amountToLoan);
    }

### Learnings - Mitigations

- We need to track that the one who triggers the loan is the `owner` of the contract! Because we cannot control the code of the Lending Borrowing pool, we can only manage our own code. Sometimes the lending function of the pool passes the `msg.sender` as parameter that can be checked as an initiator within the security checks on the beginning of `receiveEther()` function. It can look something like this example, that uses the `Ownable` modifier:

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

The best advice to solve this level is thinking about the word _trust_. Lets go back to the 90's. Would you give a blank check to Jordan Belfort? This level does the same. It is giving us a blank check...

### Solution

The vulnerability in here is on the `line 36` of the contract. The pool is giving us the chance to pick different actors as for `borrower` and `target`. Also, the weakness is that by letting us input the `calldata` we can use it to exploit the pool by relying on one function of the `ERC20` standard. The exploit can be performed into two different ways. Performing one transaction and two. We will showcase the shorter version and explain how to do the other one.

Using the _blank check_ that this contract gives us it is quite simple. We need to trigger the `flashLoan` function and pass it as `calldata` an instruction that let us transfer the tokens held on the `TrusterLenderPool`. There is one function that let us do this only when a crucial requirement is fulfilled: the `approval`. We will encode the `approval` call into the `calldata`. The key in here is that this call is coming from the pool contract and thus will be valid (because technically, you can only approve the tokens held by you, otherwise this will be a mess...), in other words the call will be done by the `msg.sender == address(pool)`. This will let either the `attacker` or the `TrustCracker.sol` contract to execute afterwards the ERC20 `transferFrom` function and drain the pool.

The basic structure to do so will be a function like this one (for interfaces initialization and how the contract should be deployed, you can check the `TrustCracker.sol`
contract under the `contracts` folder):

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

1. A receiver contract containing the `receive` function with the required structure by the pool, calls for the `flashLoan`
2. Once the tokens arrive to the receiver, internal and desired transactions are performed (e.g. arbitrage).
3. When the internal transactions are finished, the receiver contract **must** send the tokens back to the pool.

The exploit can be done in a single transaction because the `flashLoan` function does not checks that the requested amount is **greater than zero**, this makes the _step 3_ not required (because if I don't ask for tokens, I am not obliged to return anything!).

The same exploit can be done while requesting tokens (more than zero), executing the `approval` for the pool balance, returning back the requested amount and in a former transaction call the `transferFrom` method and drain the `TrusterLenderPool`.

### Learnings - Mitigations

- Respecting the `flashloan` basic contract structure is a must.
- If the pool is only lending with the `loan` function, check that the requested amount is greater than zero. _Go elsewhere to ask for zero tokenz, we ar a sekur protokol pal._
- Give a fixed calldata structure inside the `loan` function to prevent malicious calls. Do not request it as a parameter.
- To rely on logic, tokens can only be borrowed by contracts. Individual wallets cannot perform further logic such as contracts do.

**And remember, if a suited guy flexing cars and watches comes by offering huge APY's, run away. It is a scheme.**
⠀
⠀
⠀

## 4) Side Entrance Lender

### Catch - Hints

We need to look closely how does the balance of this contract is modified. Think this contract as a big water tank with two inlets of water and oil and two outlets that checks its level. It is basically saying... "if my level is constant, the mixture inside is constant". What if we decide to turn of the water inlet and fill it back with oil (keeping the outlets open). The level will remain constant but... there will no more water inside the tank! This level can be cracked by thinking how things remain constant and how they may change...

### Solution

We may trick the contract with the `deposit` and `withdraw`logic combined with the request for a `flashLoan`. If we follow this path we will be able to empty the contract:

1. Ask for a loan for its whole balance.
2. When the `execute` function is triggered, we can give the ethers back by calling `deposit`. This will make the pool balance to match the `require` condition and the `flashLoan` function will be mined completely. Also, this assigns the `SideCracker` contract a balance inside the `balances`mapping stored on the pool contract. In other words, we returned back the tokens but we assigned them as our property as for the pool logic.
3. Because we now hold a balance as our property, we can simply call the `withdraw` function and draining the pool!

The contract that exploits this pool is within the same folder as the contract of this level but the logic will be something like this:

    receive() external payable {}

    function drainPool() public {
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

Call `drainPool` and **kboom**!

### Learnings - Mitigations

- Be always wary about side entrance functions that may change the checked condition making a kind of illusionism show.
- The fact that some variables remain the same after a call it is not a sign that the new state is exactly the same.
  ⠀
  ⠀
  ⠀

## 5) The rewarder

### Catch - Hints

Think about how does a boundary case affects a value. On math, this is a border case that can be analyzed with tendency and limit algebra. 

To be more clear, what happens if there is a company that has 10,000 shares on the market and it gives dividends according the % owned of the company?

 You own 5,000 shares. So, you will be receiving a 50% of the dividends. Somehow, you manage to buy more and now you have 9,000. This means that you will be owner of the 90% of the dividends. You keep buying more and more and you finish with 9,999 shares and the founder of the company is very reluctant to sell that remaining share. You now are the owner of the 99.99% of the dividends but because of the founder, you will **never** be the owner of the 100%.

This is a border case. That 0.001% makes no difference but you won't receive all the dividends. If you can apply this logic somehow with this scenario with the given tools, you will pass this level.

**Tip:** Dividends are not paid daily, some time needs to pass!

### Solution

The same physics logic can be applied in here. The state of the rewards is refreshed at a fixed timespan. It is analogue to say that we are deducting a flow property status just by measuring it on two different times. A flowrate for example, may change and saying that it remained constant every time only by measuring the flowrate once per year is a faulty assertion!

The weakness of this contract relies on having fixed times to update the reward amounts. We can exploit it with this logic.

1) Wait until the next rewards calculation time (```5 days```).
2) Ask for a huge amount of tokens with a ```flashLoan```.
3) Use those borrowed tokens to harvest the rewards by calling ```deposit```. This will "exchange" our ```liquidity``` tokens for ```accounting``` ones. Because the ```amountBorrowed >>>> totalDepositsBefore```, the boundary limit by tendency will assign us a really big amount of tokens (more than the 99% of them).
4) To return the loan (made in ```liquidity``` tokens), we can call the ```withdraw```function that burns the ```accounting``` tokens and gives us back the ```liquidity``` ones.
5) Transfer the ```rewardTokens``` from the contract right to the ```attacker``` (us) and that's it!

The functions behind this logic:

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

### Learnings - Mitigations
- Prevent depending on fixed timeframes where the rewards are updated. In other words, having a logic that relies on a single point of time instead of having a continuous updates of the data the rewards allocation can be manipulated by a flash loans.
- Thinking about border scenarios regarding fractions is useful to come up with border situations that may break that math and other logic dependant steps.