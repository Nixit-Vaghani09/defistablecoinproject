// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/*
 *Title : DSCEngine
 *Author : Nixit Vaghani
 *Description :
 *
 *this system is designed to be as minimal as possible , here the tokens ae maintained as 1 token == 1$ peg all the time.
 *
 *
 *this stablecoin properties are :
 * Exogenous Collateral
 * Dollar Pegged
 * Algorithmically stable
 *
 *Our DSC system should always be "overcollateralized". At no point, should the value of
 *all collateral < the $ backed value of all the DSC.
 *
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine {
    ////////////////
    //   errors  //
    ///////////////
    error DSCEngine__AmmountCannotBeZero();
    error DSCEngine__TokenAndPriceFeedLengthDonotMatch();
    error DSCEnigne__MintingFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__HealthFactorIsBroken(address user, uint256 healthFactor);
    error DSCEngine__HealthFactorIsOkay();
    error DSCEngine__HealthFactorNotImproved();


    ////////////////////
    //     Types      // 
    ////////////////////
    using OracleLib for AggregatorV3Interface;
    ///////////////////////
    //STATE VAARAIBLES   //
    ///////////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    DecentralizedStableCoin i_dsc;

    ////////////////
    // mappings   //
    ////////////////
    // @dev mapping of token address to price feed address
    mapping(address collateralAddress => address priceFeed) public s_priceFeeds;
    //@dev mapping of user address to collateral tooken address to amount of collateral deposited
    mapping(address user => mapping(address collaateralToken => uint256 amount))
        public s_userCollateralBalance;
    //@dev mapping of user address to amount of dsc minted
    mapping(address user => uint256 amount) public s_DSCMinted;

    //@dev if we know how many tokens we have we can make it unmutable
    address[] public s_collateralTokens;

    ////////////////
    // Events     //
    ////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed tokenCollateralAddress,
        uint256 amount
    );

    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed tokenCollateralAddress,
        uint256 amount
    );

    //if redeemFrom != redeemTo then it was liquidated

    ////////////////
    // Modifiers  //
    ////////////////

    modifier AmountMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__AmmountCannotBeZero();
        }
        _;
    }

    modifier ValidTokenAddress(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    ////////////////
    // functions  //
    ////////////////

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address dscAddress
    ) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAndPriceFeedLengthDonotMatch();
        }
        for (uint i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////
    // Exteranl Functions   //
    //////////////////////////

    /*
    *@param : tokenCollateralAddress - The ERC20 token address of the collatreal you are depositing
    *@param : amountOfCollateral - The amount of collateral you are depositing
    *@param : amount ofDSC - The amount of DSC you want to mint
    @notice this function will deposit collateral and mint DSC in one transaction
      */
    function depositcollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountOfCollateral,
        uint256 amountOfDSC
    ) external {
        depositCollateral(tokenCollateralAddress, amountOfCollateral);
        mintdsc(amountOfDSC);
    }

    /*
     *@param : amount - The amount of DSC you want to burn
     *@notice careful ! you will burn your DSC here !! Do it only if you want it.
     *@dev you might want to use this if you're nervous you might get liquidated and want to just burn
     *your DSC but keep your collateral in.
     */
    function burndsc(uint256 amount) external AmountMoreThanZero(amount) {
        _burndsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     *@param : collateral - The ERC20 address of the collateral you are using to make the system solvent again
     *this are also the collateral you will recieve from the user who is insolvent.
     *For the  Collateral you are going to burn your own DSC and you can't liquidate yourself
     *
     *@param : user - The address of the user you want to liquidate
     *@param : debtToCover - The amount of DSC you want to burn on behalf of 'user'
     *
     *
     *
     *@notice : you can practicaly liquidate a user
     *@notice : you will get a 10% liquidation bonus for taking the user's fund
     *@notice : this function assumes the system is 150% overcollateralized in order fpr the system to work.
     *@notice : a known bug is if the protocol was only 100% collateralized , we wont able to liquidate anyone
     *For example if the price of collateral plummeted before anyone can be liquidated
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external AmountMoreThanZero(debtToCover) ValidTokenAddress(collateral) {
        uint256 startinguserHealthFactor = _healthFactor(user);
        if (startinguserHealthFactor >= 1e18) {
            revert DSCEngine__HealthFactorIsOkay();
        }
        //If covering 100 DSC  , we need to cover ,$100 collateral

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSDValue(
            collateral,
            debtToCover
        );
        //and giving a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        //burndsc to equal to debtToCover
        //Figure out hiw much collateral we need to recover based on the amount of DSC burn
        _redeemCollateral(
            collateral,
            tokenAmountFromDebtCovered + bonusCollateral,
            user,
            msg.sender
        );

        _burndsc(debtToCover, user, msg.sender);
        uint256 userEndingHealthFactor = _healthFactor(user);
        //this condition may nevr hit but for safetywe will check health factor is improving after liquidation
        if (userEndingHealthFactor <= startinguserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param tokenCollateralAddress : the ERC20 address of collateral you are redeeming
     * @param amount : total number of collateral tokens you want to redeem
     * @notice : this function will redeem your collateral .
     * @notice : if you have DSC minted you won't be able to redeem your collateral until you burn your DSC
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amount
    )
        external
        AmountMoreThanZero(amount)
        ValidTokenAddress(tokenCollateralAddress)
    {
        _redeemCollateral(
            tokenCollateralAddress,
            amount,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param tokenCollateralAddress : the ERC20 address of collateral you are redeeming
     * @param amountCollateral : total number of collateraltokens you are redeeming
     * @param amountDSC : the amount of DSC you are burning in order to redeem your collateral
     * @notice : this function will burn your dsc and redeem your collateral .
     */
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSC
    )
        external
        AmountMoreThanZero(amountCollateral)
        ValidTokenAddress(tokenCollateralAddress)
    {
        _burndsc(amountDSC, msg.sender, msg.sender);
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////
    // PUBLIC FUNCTIONS  //
    ///////////////////////

    /*
    *@param : amount - The amount of DSC you want to mint
    you can only mint DSC if you have enough collaateral
    */
    function mintdsc(uint256 amount) public AmountMoreThanZero(amount) {
        s_DSCMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amount);
        if (minted == false) {
            revert DSCEnigne__MintingFailed();
        }
    }

    /*
     *@param: tokenCollateralAddress - The ERC20 token address of the collateral you are depositing
     *@param: amount - The amount of collateral you are depositing
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amount
    )
        public
        ValidTokenAddress(tokenCollateralAddress)
        AmountMoreThanZero(amount)
    {
        s_userCollateralBalance[msg.sender][tokenCollateralAddress] += amount;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (success == false) {
            revert DSCEngine__TransferFailed();
        }
    }

    ////////////////////////
    // PRIVATE FUNCTIONS  //
    ////////////////////////

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amount,
        address from,
        address to
    ) private {
        s_userCollateralBalance[from][tokenCollateralAddress] -= amount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burndsc(
        uint256 amountOfDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountOfDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountOfDscToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountOfDscToBurn);
    }

    ///////////////////////////////////////////////
    // PRIVATE & INTERNAL PURE & VIEW FUNCTIONS  //
    ///////////////////////////////////////////////
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDSCMinted,
            uint256 totalCollateralValueInUSD
        ) = getAccountInformation(user);
        return
            _calculateHealthFactor(totalCollateralValueInUSD, totalDSCMinted);
    }

    function _getUSDValue(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        //1ETH = 2000 USD
        //MOST USD pairs have 8 decimals , we would pretend all of them have
        //We want to have everything in terms of WEI so we add 10 zeros at the end
        return
            (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function _calculateHealthFactor(
        uint256 collateralValueInUSD,
        uint256 DSCMinted
    ) internal pure returns (uint256) {
        if (DSCMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / DSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(user, healthFactor);
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValue(user);
    }

    //External and public view and pure  functions

    function calculateHealthFactor(
        uint256 collateralValueInUSD,
        uint256 DSCMinted
    ) external pure returns (uint256) {
        return _calculateHealthFactor(collateralValueInUSD, DSCMinted);
    }

    function getAccountInformation(
        address user
    )
        public
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
    {
        return _getAccountInformation(user);
    }

    function getUSDValue(
        address token,
        uint256 amount // inwei
    ) external view returns (uint256) {
        return _getUSDValue(token, amount);
    }

    function getCollateralBalance(
        address user,
        address token
    ) external view returns (uint256) {
        return s_userCollateralBalance[user][token];
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256) {
        uint256 totalCollateralValueInUSD;
        for (uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_userCollateralBalance[user][token];
            totalCollateralValueInUSD += _getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getTokenAmountFromUSDValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return
            (amount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getMinHealthFactor() public pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getPrecision() public pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() public pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() public pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() public pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getDSC() public view returns (address) {
        return address(i_dsc);
    }

    function getCollataeralTokenPriceFeed(
        address token
    ) public view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }
}
