//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {console} from "forge-std/Config.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is Test {
    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed tokenCollateralAddress,
        uint256 amount
    );

    event CollateralDeposited(
        address indexed user,
        address indexed tokenCollateralAddress,
        uint256 amount
    );

    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUSDPriceFeed;
    address public btcUSDPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address user = address(1);

    uint256 constant STARTING_BALANCE = 10 ether;

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

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

        if (block.chainid == 31337) {
            vm.deal(user, STARTING_BALANCE);
        }

        ERC20Mock(weth).mint(user, STARTING_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_BALANCE);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /////////////////////////
    //  Constructor test   //
    /////////////////////////

    function testRevertsIfTokenLengthDoesntMatchesPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);
        vm.expectRevert(
            DSCEngine.DSCEngine__TokenAndPriceFeedLengthDonotMatch.selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////////////
    //       Price Test        //
    /////////////////////////////

    function testGetTokenAmountFromUsd() public {
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUSDValue(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    function testGetUSDValue() public {
        uint256 wethAmount = 15 ether;
        uint256 expectedUsd = 30000e18;
        uint256 usdValue = dsce.getUSDValue(weth, wethAmount);
        assertEq(expectedUsd, usdValue);
    }

    ///////////////////////////////////
    //    Deposit Collateral Test    //
    ///////////////////////////////////

    // 1. collateralTotalAmount for user being updated or not.
    // 2. Event being emitted or not.
    // 3. Error revertion on transactions failure.
    // 4. Function reverting if collTERl token amount is <= 0.
    // 5. Function reverting if token not found.

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockCollateralToken = new MockFailedTransferFrom();
        tokenAddresses = [address(mockCollateralToken)];
        priceFeedAddresses = [ethUSDPriceFeed];
        // DSCEngine receives the third parameter as dscAddress, not the tokenAddress used as collateral.
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        mockCollateralToken.mint(user, amountCollateral);
        vm.startPrank(user);
        ERC20Mock(address(mockCollateralToken)).approve(
            address(mockDsce),
            amountCollateral
        );
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(
            address(mockCollateralToken),
            amountCollateral
        );
        vm.stopPrank();
    }

    function testRevertDepositCollateralIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__AmmountCannotBeZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", user, 100e18);
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__TokenNotAllowed.selector,
                address(randToken)
            )
        );
        dsce.depositCollateral(address(randToken), amountCollateral);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(weth), amountCollateral);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositcollateralAndMintDSC(
            address(weth),
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
        _;
    }

    function testUserCanMintWithoutMinting() public depositCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testUserCanMintDSCAfterCollateralization()
        public
        depositCollateralAndMintDsc
    {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    function testUserCanGetInfoAfterDepositCollateral()
        public
        depositCollateral
    {
        (uint256 dscMinted, uint256 collateralValueInUSD) = dsce
            .getAccountInformation(user);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUSDValue(
            address(weth),
            collateralValueInUSD
        );
        assertEq(0, dscMinted);
        assertEq(expectedDepositedAmount, amountCollateral);
    }

    function testEmitsEventCorrectlyOnCollateralDeposited() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectEmit(true, true, false, true, address(dsce));
        emit CollateralDeposited(user, address(weth), amountCollateral);

        dsce.depositCollateral(address(weth), amountCollateral);
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //   Deposit Collateral And Mint DSC Test //
    ////////////////////////////////////////////

    // 1. Check functions revert if the healthfactor is low
    // 2. Check if the functions updates user balance

    function testIfRevertsIfHealthFactorIsLow() public {
        (, int256 price, , , ) = MockV3Aggregator(ethUSDPriceFeed)
            .latestRoundData();
        amountToMint =
            (amountCollateral *
                (uint256(price) * dsce.getAdditionalFeedPrecision())) /
            dsce.getPrecision();

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            dsce.getUSDValue(weth, amountCollateral),
            amountToMint
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsBroken.selector,
                user,
                expectedHealthFactor
            )
        );
        dsce.depositcollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testCanMintWithDepositedCollateral()
        public
        depositCollateralAndMintDsc
    {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    /////////////////////////////////
    //         Mint DSC            //
    /////////////////////////////////

    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUSDPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEnigne__MintingFailed.selector);
        mockDsce.depositcollateralAndMintDSC(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
    }

    function testCannotMintIfAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmmountCannotBeZero.selector);
        dsce.mintdsc(0);
        vm.stopPrank();
    }

    function testIfHealthFactorIsBroken() public depositCollateral {
        (, int256 price, , , ) = MockV3Aggregator(ethUSDPriceFeed)
            .latestRoundData();
        amountToMint =
            (uint256(price) *
                amountCollateral *
                dsce.getAdditionalFeedPrecision()) /
            dsce.getPrecision();

        vm.startPrank(user);
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            dsce.getUSDValue(weth, amountCollateral),
            amountToMint
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsBroken.selector,
                user,
                expectedHealthFactor
            )
        );
        dsce.mintdsc(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositCollateral {
        vm.prank(user);
        dsce.mintdsc(amountToMint);

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    function testCannotWithoutDepositingCollateral() public {
        vm.startPrank(user);
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            0,
            amountToMint
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsBroken.selector,
                user,
                expectedHealthFactor
            )
        );
        dsce.mintdsc(amountToMint);
        vm.stopPrank();
    }

    /////////////////////////////////////
    //          Burn DSC TEST          //
    /////////////////////////////////////

    function testRevertIfAmountToBurnIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositcollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__AmmountCannotBeZero.selector);
        dsce.burndsc(0);
        vm.stopPrank();
    }

    function testCannotBurnMoreThanWhatUserHas() public {
        vm.startPrank(user);
        vm.expectRevert();
        dsce.burndsc(1);
        vm.stopPrank();
    }

    function testCanBurnDsc() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositcollateralAndMintDSC(
            address(weth),
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
        vm.startPrank(user);
        uint256 initialBalance = dsc.balanceOf(user);
        assertEq(initialBalance, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.burndsc(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    /////////////////////////////////////
    //     redeem collateral test      //
    /////////////////////////////////////

    function testMockFailedTransfer() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUSDPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(user, amountCollateral);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(
            address(mockDsce),
            amountCollateral
        );
        // Act / Assert
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
    }

    function testRevertIfAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositcollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__AmmountCannotBeZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositCollateral {
        vm.startPrank(user);
        uint256 userBalance = dsce.getCollateralBalance(user, weth);
        assertEq(userBalance, amountCollateral);
        dsce.redeemCollateral(weth, amountCollateral);
        uint256 userBalanceafterRedeem = dsce.getCollateralBalance(user, weth);
        assertEq(userBalanceafterRedeem, 0);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs()
        public
        depositCollateral
    {
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralRedeemed(user, user, weth, amountCollateral);
        vm.startPrank(user);
        dsce.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    ///////////////////////////////////////////////
    //     Redeem collateral for dsc test        //
    ///////////////////////////////////////////////

    function testMustReedemMoreThanZero() public depositCollateralAndMintDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__AmmountCannotBeZero.selector);
        dsce.redeemCollateralForDSC(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemCollateralForDSC()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(user);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    /////////////////////////////////
    //      Health Factor test     //
    /////////////////////////////////

    function testProperlyReportsHealthFactor()
        public
        depositCollateralAndMintDsc
    {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dsce.getHealthFactor(user);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne()
        public
        depositCollateralAndMintDsc
    {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dsce.getHealthFactor(user);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    ////////////////////////////////////////
    //         Liquidation test           //
    ////////////////////////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUSDPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUSDPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce), amountCollateral);
        mockDsce.depositcollateralAndMintDSC(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDsce.depositcollateralAndMintDSC(
            weth,
            collateralToCover,
            amountToMint
        );
        mockDsc.approve(address(mockDsce), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDsce.liquidate(weth, user, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor()
        public
        depositCollateralAndMintDsc
    {
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositcollateralAndMintDSC(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOkay.selector);
        dsce.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositcollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 updatedWethValue = 18e8;
        vm.startPrank(liquidator);
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(updatedWethValue);
        uint256 healthFactor = dsce.getHealthFactor(user);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        dsce.depositcollateralAndMintDSC(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, user, amountToMint);
        vm.stopPrank();

        _;
    }

    function LiquidationPayOutIsCorrect() public liquidated {
        uint256 liquidatorBalanceWethBalance = ERC20Mock(weth).balanceOf(
            liquidator
        );
        uint256 expectedWeth = dsce.getTokenAmountFromUSDValue(
            weth,
            amountToMint
        ) +
            ((dsce.getTokenAmountFromUSDValue(weth, amountToMint) *
                dsce.getLiquidationBonus()) / dsce.getLiquidationPrecision());
        uint256 hardcodeExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorBalanceWethBalance, hardcodeExpected);
        assertEq(liquidatorBalanceWethBalance, expectedWeth);
    }

    function testUserHasStillSomeEthLeftAfterLiquidation() public liquidated {
        uint256 amountLiquidated = dsce.getTokenAmountFromUSDValue(
            weth,
            amountToMint
        ) +
            ((dsce.getTokenAmountFromUSDValue(weth, amountToMint) *
                dsce.getLiquidationBonus()) / dsce.getLiquidationPrecision());
        console.log(amountLiquidated);
        uint256 usdAmountLiquidated = dsce.getUSDValue(weth, amountLiquidated);
        console.log(usdAmountLiquidated);
        uint256 expectedUserCollateralValueInUSD = dsce.getUSDValue(
            weth,
            amountCollateral
        ) - usdAmountLiquidated;
        console.log(expectedUserCollateralValueInUSD);
        (, uint256 userCollateralValueInUSD) = dsce.getAccountInformation(user);
        console.log(userCollateralValueInUSD);
        assertEq(expectedUserCollateralValueInUSD, userCollateralValueInUSD);
    }

    function testLiquidatorTakesOnUserDebt() public liquidated {
        (uint256 liquidatedAmount, ) = dsce.getAccountInformation(liquidator);
        assertEq(liquidatedAmount, amountToMint);
    }

    function testUserHasNotDebt() public liquidated {
        (uint256 userDscMinted, ) = dsce.getAccountInformation(user);
        assertEq(userDscMinted, 0);
    }

    /////////////////////////////////////////
    //     View & pure Function test       //
    /////////////////////////////////////////

    function testValueOfMinimumHealthFactor() public {
        uint256 healthFactor = dsce.getMinHealthFactor();
        assertEq(healthFactor, 1 ether);
    }

    function testValueOfLiquidationFactor() public {
        uint256 liquidationBonus = dsce.getLiquidationBonus();
        assertEq(liquidationBonus, 10);
    }

    function testValueOfPrecision() public {
        uint256 precision = dsce.getPrecision();
        assertEq(precision, 1 ether);
    }

    function testValueOfAdditionalFeedPrecision() public {
        uint256 additionalFeedPrecision = dsce.getAdditionalFeedPrecision();
        assertEq(additionalFeedPrecision, 1e10);
    }

    function testValueOfLiquidationThreshold() public {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, 50);
    }

    function testValueOfLiquidationPrecision() public {
        uint256 liquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(liquidationPrecision, 100);
    }

    function testValueOfDSC() public {
        address i_dsc = dsce.getDSC();
        assertEq(i_dsc, address(dsc));
    }

    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = dsce.getCollataeralTokenPriceFeed(address(weth));
        assertEq(priceFeed, ethUSDPriceFeed);
    }

    function testCollateralBalance() public depositCollateral {
        uint256 ethBalance = dsce.getCollateralBalance(user, weth);
        assertEq(ethBalance, 10 ether);
    }

    function testCollateralToken() public {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testValueOfAccountCollateral() public depositCollateral {
        uint256 expectedCollateralValue = dsce.getUSDValue(
            weth,
            amountCollateral
        );
        (, uint256 collateralValue) = dsce.getAccountInformation(user);
        assertEq(expectedCollateralValue, collateralValue);
    }

    function testTotalCollateralValue() public depositCollateral {
        vm.startPrank(user);
        ERC20Mock(wbtc).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(wbtc), amountCollateral);
        vm.stopPrank();
        uint256 totalValue = dsce.getAccountCollateralValue(user);
        uint256 expectedValue = 30000 ether;
        // here our weth  , 1weth = $2000
        // here our wbtc  , 1wbtc = $1000
        // and our 1USD , $1 = 1e18 = 1ether
        assertEq(totalValue, expectedValue);
    }
}
