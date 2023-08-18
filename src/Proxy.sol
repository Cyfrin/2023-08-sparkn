// SPDX-License-Identifier: BUSL-1.1

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

/**
 * @title Proxy contract
 * @notice This contract is created and paired with every contest in SPARKN.
 * This disposable contract is supposed to be used during the contest's life cycle.
 * After the contest is over, this contract will not be used anymore.
 * In case somebody may send token to this contract by mistake, we added a function
 * in Distributor contract to distribute the token after the contest is over.
 * @dev This contract is the proxy contract which will be deployed by factory contract.
 * This contract is based on OpenZeppelin's Proxy contract.
 * This contract is designed to be with minimal logic in it and in this way,
 * it can prevent functions' signature collision.
 */
contract Proxy {
    // implementation address
    address private immutable _implementation;

    /// @notice constructor
    /// @dev set implementation address
    constructor(address implementation) {
        _implementation = implementation;
    }

    /**
     * @dev Delegate all the calls to implementation contract
     */
    fallback() external {
        address implementation = _implementation;
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), implementation, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}
