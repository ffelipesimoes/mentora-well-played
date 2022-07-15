// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract PriceConsumerMaticDollar {

    uint8 DataDecimal;
    uint8 public decimalValue =18;
    AggregatorV3Interface internal priceFeed;
    /**
     * Network: MUMBAI
     * Aggregator: MATIC/USD
     * Address: 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada
     */
    constructor(address _aggregator) {
        priceFeed = AggregatorV3Interface(_aggregator);
        decimalValue = 18;
    }

    function decimalValueData() public returns (uint8){
        DataDecimal = priceFeed.decimals();
        return DataDecimal;
    }
    /**
     * Returns the latest price
     */
    function getPriceDolarperMaticLink()  public view returns (int256) {
        (
            /*uint80 roundID*/,
            int256 _price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return _price;
    }

    function getPriceDolarperMatic() public view returns(uint){
        int256 price = getPriceDolarperMaticLink()* 10**10;
        return SafeCast.toUint256(price);
    }

    function getPriceMaticperDolar() public view returns (uint){
        int256 _price = getPriceDolarperMaticLink();
        int256 dec = 10**26;
        uint cast = SafeCast.toUint256(dec/_price);
        return cast;
    }

    function getPriceUSD(uint maticwei) public view returns(uint){
        uint price = maticwei * getPriceDolarperMatic()/10**18;  
        return price;
    }

    function getPriceMATIC(uint usdwei) public view returns(uint){
        uint matic = usdwei *  getPriceMaticperDolar()/10**18;
        return matic;
    }

}