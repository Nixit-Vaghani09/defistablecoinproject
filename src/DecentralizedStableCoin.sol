//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
*  Title : De - Centralized Stable Coin
*  Author : Nixit Vaghani
*  Collateral : Exogenous : (WETH , WBTC)  
*  Minting : Algorithmic
*  Relative Stability : Pegged to USD

This contract is meant to be governed by DSCEngine . This is just an ERC20 impementtation of the stable coin
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    //ERRORS

    error DecentralizedStableCoin__AddressCannotBeZero();
    error DecentralizedStableCoin__AmmountCannotBeZero();
    error DecentralizedStableCoin__AmmountExceedsAccountBalance();

    constructor() ERC20("DecenteralizedFinanceCoin", "DFC") Ownable(msg.sender){}

    /*@param account : The address to which the staable coin are to be minted
     *@ param amount : The total amount of the stable coin to be minted to the account
     *@ notice : This function should only be called by the DSCEngine contract .
     */
    function mint(
        address account,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (account == address(0)) {
            revert DecentralizedStableCoin__AddressCannotBeZero();
        }
        if (amount == 0) {
            revert DecentralizedStableCoin__AmmountCannotBeZero();
        }
        _mint(account, amount);
        return true;
    }

    /*@param account : the account whose stable coins are to be burned .
     * @param amount : the total amount of the stable coin to be burned .
     * @notice : This function should only be called by the DSCEngine contract .
     */
    function burn(
        address account,
        uint256 amount
    ) public  onlyOwner returns (bool) {
        uint256 balance = balanceOf(account);
        if (account == address(0)) {
            revert DecentralizedStableCoin__AddressCannotBeZero();
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin__AmmountCannotBeZero();
        }
        if (amount > balance) {
            revert DecentralizedStableCoin__AmmountExceedsAccountBalance();
        }
        _burn(account, amount);
        return true;
    }
}
