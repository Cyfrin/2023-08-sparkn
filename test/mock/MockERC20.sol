// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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
// view & pure functions

pragma solidity 0.8.18;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

/*
 * @title MockERC20
 * @author CodeFox
 * @dev this is a random ERC20 token for testing purposes
 * This can be supposed to be an stable coin in the current system 
 */
contract MockERC20 is ERC20, Ownable {
    error MockERC20__AmountMustBeMoreThanZero();

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_amount == 0) {
            revert MockERC20__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
