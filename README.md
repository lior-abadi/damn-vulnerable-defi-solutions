![](cover.png)
Created by [@tinchoabbate](https://twitter.com/tinchoabbate)
Visit [damnvulnerabledefi.xyz](https://damnvulnerabledefi.xyz)

# Solutions

## 1) Unstoppable
### Catch - Hints
The issue in here is considering that the only way to send funds to the ```UnstoppableLender.sol``` contract is by executing the ```depositTokens``` (with a structure composed by a ```transferFrom``` method). There are many ways to make transactions that involve ERC20 tokens. Going from regular transactions to more creative ways such as selfdestructing contracts or predestinating funds!

### Solution
The ```flashLoan``` function seems fair but for one line. On ```line 40```, a local variable which state is updated on other function. The variable ```poolBalance``` is the weak point of this contract. It is only updated when the pool receives *DVT's* by calling the ```depositTokens```function. What happens if we send *DTV's* with a regular compliant ERC20 ```transfer```method? Or if we create a contract, deposit the *DVT's* and selfdestruct the contract towards the ```UnstoppableLender.sol``` contract? Exactly, the ```balanceOf(DVT's)``` inside the lending pool will be increased and this change won't be tracked by the poorly implemented ```poolBalance``` state.

### Learnings
- If we are checking a strict equality or inequality, analyze from where, who and when can manipulate each parts of the equation and evaluate if the malicious outcomes can be triggered. 
- This also is very common with ```require``` statements that are bypassed by tricking using a little bit of math and blockchain knowledge and also to unexpectedly enter ```if``` statements executions. 