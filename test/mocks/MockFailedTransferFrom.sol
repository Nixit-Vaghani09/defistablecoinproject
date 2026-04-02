//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {ERC20,ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
contract MockFailedTransferFrom is ERC20Burnable,Ownable{
error DecentralizedStableCoin__AddressCannotBeZero();
    error DecentralizedStableCoin__AmmountCannotBeZero();
    error DecentralizedStableCoin__AmmountExceedsAccountBalance();

    constructor() ERC20("DecenteralizedFinanceCoin", "DFC") Ownable(msg.sender){}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert  DecentralizedStableCoin__AmmountCannotBeZero();
        }
        if (balance < _amount) {
            revert  DecentralizedStableCoin__AmmountExceedsAccountBalance();
        }
        super.burn(_amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function transferFrom(
        address, /*sender*/
        address, /*recipient*/
        uint256 /*amount*/
    )
        public
        pure
        override
        returns (bool)
    {
        return false;
    }
}
