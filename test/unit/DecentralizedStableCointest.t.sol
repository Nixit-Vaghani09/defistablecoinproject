//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DecentralizedStablecoinTest is StdCheats, Test {
    DecentralizedStableCoin dsc;

    function setUp() public {
        dsc = new DecentralizedStableCoin();

    }

    //////////////////////////////////////
    //             Mint TEST            // 
    //////////////////////////////////////

    function testMustMintMoreThanZero() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmmountCannotBeZero.selector);
        dsc.mint(address(this),0);
        vm.stopPrank();
    }

    function testCannotMintToZeroAddress() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AddressCannotBeZero.selector);
        dsc.mint(address(0),100);
        vm.stopPrank();
    }

    function testReturnTrueOnMint() public {
        vm.startPrank(dsc.owner());
        bool result=dsc.mint(address(this),100);
        vm.stopPrank();
        assertEq(result,true);
    }


    ////////////////////////////////////////
    //             Burn TEST              // 
    ////////////////////////////////////////

    function testMustBurnMoreThanZero() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this),100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmmountCannotBeZero.selector);
        dsc.burn(address(this),0);
        vm.stopPrank();

    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmmountExceedsAccountBalance.selector);
        dsc.burn(address(this),101);
        vm.stopPrank();
    }

    function testCannotBurnOnAddressZero() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this),100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AddressCannotBeZero.selector);
        dsc.burn(address(0),100);
        vm.stopPrank();
    }
    function testReturnTrueOnBurn() public {
        vm.startPrank(dsc.owner());
        bool resultMint=dsc.mint(address(this),100);
        bool resultBurn=dsc.burn(address(this),10);
        vm.stopPrank();
        assertEq(resultMint,true);
        assertEq(resultBurn,true);
    }

}