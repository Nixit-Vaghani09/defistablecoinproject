//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {Test} from "forge-std/Test.sol";

contract StopOnRevertHandler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    MockV3Aggregator public ethUSDPriceFeed;
    MockV3Aggregator public btcUSDPriceFeed;

    address[] public userWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();

        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUSDPriceFeed = MockV3Aggregator(
            dsce.getCollataeralTokenPriceFeed(address(weth))
        );
        btcUSDPriceFeed = MockV3Aggregator(
            dsce.getCollataeralTokenPriceFeed(address(wbtc))
        );
    }

    function mintAndDepositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        // must be more than 0
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);

        userWithCollateralDeposited.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralBalance = dsce.getCollateralBalance(
            msg.sender,
            address(collateral)
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralBalance);
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function burnDsc(uint256 amountDsc) public {
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        if (amountDsc == 0) return;
        vm.startPrank(msg.sender);
        dsc.approve(address(dsce), amountDsc);
        dsce.burndsc(amountDsc);
        vm.stopPrank();
    }

    function liquidate(
        uint256 collateralSeed,
        address userToBeLiquidated,
        uint256 debtToCover
    ) public {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        uint256 userHealthFactor = dsce.getHealthFactor(userToBeLiquidated);
        if (userHealthFactor >= minHealthFactor) {
            return;
        }
        debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        dsce.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    function transferDsc(uint256 amountDsc, address to) public {
        if (to == address(0)) {
            to = address(1);
        }
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        vm.prank(msg.sender);
        dsc.transfer(to, amountDsc);
    }

    function updateCollateralPrice(
        uint96 newPrice,
        uint256 collateralSeed
    ) public {
        int256 intNewPrice = int256(uint256(newPrice));
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(
            dsce.getCollataeralTokenPriceFeed(address(collateral))
        );
        priceFeed.updateAnswer(intNewPrice);
    }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
