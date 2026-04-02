// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedMintDSC is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AddressCannotBeZero();
    error DecentralizedStableCoin__AmmountCannotBeZero();
    error DecentralizedStableCoin__AmmountExceedsAccountBalance();

    
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmmountCannotBeZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__AmmountExceedsAccountBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__AddressCannotBeZero();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmmountCannotBeZero();
        }
        _mint(_to, _amount);
        return false;
    }
}
