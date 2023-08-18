// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ERC20Mock} from "openzeppelin/mocks/ERC20Mock.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Proxy} from "../../src/Proxy.sol";

/// test the proxy contract when it is alone
contract ProxyTest is StdCheats, Test {
    Proxy public proxy;
    Proxy public secondProxy;
    Proxy public thirdProxy;

    function setUp() public {
        // deploy contracts
        proxy = new Proxy(address(1));
        secondProxy = new Proxy(makeAddr('randomImplementation'));
        thirdProxy = new Proxy(makeAddr('randomImplementation2'));
    }

    /// expected failing pattern
    function testIfCallingFunctionDoesntExistThenRevert() public {
        // test something
        vm.expectRevert();
        (bool success,) = address(proxy).call(abi.encodeWithSignature("nonExistingFunction()"));
        // console.log(success);
        assertEq(success, false);
    }

    function testIfCallingFunctionDoesntExistThenRevertPattern2() public {
        // test something
        vm.expectRevert();
        (bool success,) = address(proxy).call(abi.encodeWithSignature("getConstants()"));
        // console.log(success);
        assertEq(success, false);
        vm.expectRevert();
        (bool success2,) = address(secondProxy).call(abi.encodeWithSignature("getConstants()"));
        // console.log(success);
        assertEq(success2, false);
    }

    function testIfSendEtherToProxyThenRevert() public {
        vm.deal(msg.sender, 2 ether);
        vm.expectRevert();
        (bool success,) = address(proxy).call{value: 1 ether}("");
        // no ether arrived
        assertEq(0, address(proxy).balance);

        (bool success2,) = address(secondProxy).call{value: 1 ether}("");
        // no ether arrived
        assertEq(0, address(secondProxy).balance);
    }
}
