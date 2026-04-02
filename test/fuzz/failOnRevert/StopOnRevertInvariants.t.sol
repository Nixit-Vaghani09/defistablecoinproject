//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {StopOnRevertHandler} from "./StopOnRevertHandler.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract StopOnReverInvariants is StdInvariant,Test {
     
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    StopOnRevertHandler public handler;


    address public ethUSDPriceFeed;
    address public btcUSDPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address user = address(1);

    uint256 constant STARTING_BALANCE = 10 ether;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (
            ethUSDPriceFeed,
            btcUSDPriceFeed,
            weth,
            wbtc,
            deployerKey
        ) = helperConfig.activeNetworkConfig();

         handler = new StopOnRevertHandler(dsce, dsc);
        targetContract(address(handler));

        
    }

    function invariant_protocolMustHaveMoreThanTotalSupplyDollar() public view {
         uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUSDValue(weth, wethDeposted);
        uint256 wbtcValue = dsce.getUSDValue(wbtc, wbtcDeposited);

        
        assert(wethValue + wbtcValue >= totalSupply);
    }
}