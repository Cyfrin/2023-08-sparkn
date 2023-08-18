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

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {Proxy} from "./Proxy.sol";

/**
 * @title ProxyFactory contract
 * @notice This contract is the main entry point for users to use SPARKN's contracts.
 * @notice It will be used to deploy proxy contracts for every contest in SPARKN.
 * @dev This contract is the factory contract which will be used to deploy proxy contracts.
 */
contract ProxyFactory is Ownable, EIP712 {
    //////////////////////
    /////// Error ////////
    //////////////////////
    error ProxyFactory__NoEmptyArray();
    error ProxyFactory__NoZeroAddress();
    error ProxyFactory__CloseTimeNotInRange();
    error ProxyFactory__InvalidSignature();
    error ProxyFactory__ContestIsAlreadyRegistered();
    error ProxyFactory__ContestIsNotClosed();
    error ProxyFactory__ContestIsNotRegistered();
    error ProxyFactory__ContestIsNotExpired();
    error ProxyFactory__DelegateCallFailed();
    error ProxyFactory__ProxyAddressCannotBeZero();

    /////////////////////
    /////// Event ///////
    /////////////////////
    event SetContest(
        address indexed organizer, bytes32 indexed contestId, uint256 closeTime, address indexed implementation
    );
    event Distributed(address indexed proxy, bytes data);

    ////////////////////////////////
    /////// State Variables ////////
    ////////////////////////////////
    // contest distribution expiration
    uint256 public constant EXPIRATION_TIME = 7 days;
    uint256 public constant MAX_CONTEST_PERIOD = 28 days;

    /// @notice record contest close time by salt
    /// @dev The contest doesn't exist when value is 0
    mapping(bytes32 => uint256) public saltToCloseTime;
    /// @dev record whitelisted tokens
    mapping(address => bool) public whitelistedTokens;

    ////////////////////////////
    /////// Constructor ////////
    ////////////////////////////
    /**
     * @notice The constructor will set the whitelist tokens. e.g. USDC, JPYCv1, JPYCv2, USDT, DAI
     * @notice the array is not supposed to be so long because only major tokens will get listed
     * @param _whitelistedTokens The tokens array to get whitelisted
     */
    constructor(address[] memory _whitelistedTokens) EIP712("ProxyFactory", "1") Ownable() {
        if (_whitelistedTokens.length == 0) revert ProxyFactory__NoEmptyArray();
        for (uint256 i; i < _whitelistedTokens.length;) {
            if (_whitelistedTokens[i] == address(0)) revert ProxyFactory__NoZeroAddress();
            whitelistedTokens[_whitelistedTokens[i]] = true;
            unchecked {
                i++;
            }
        }
    }

    ////////////////////////////////////////////
    /////// External & Public functions ////////
    ////////////////////////////////////////////
    /**
     * @notice Only owner can set contest's properties
     * @notice close time must be less than 28 days from now
     * @dev Set contest close time, implementation address, organizer, contest id
     * @dev only owner can call this function
     * @param organizer The owner of the contest
     * @param contestId The contest id
     * @param closeTime The contest close time
     * @param implementation The implementation address
     */
    function setContest(address organizer, bytes32 contestId, uint256 closeTime, address implementation)
        public
        onlyOwner
    {
        if (organizer == address(0) || implementation == address(0)) revert ProxyFactory__NoZeroAddress();
        if (closeTime > block.timestamp + MAX_CONTEST_PERIOD || closeTime < block.timestamp) {
            revert ProxyFactory__CloseTimeNotInRange();
        }
        bytes32 salt = _calculateSalt(organizer, contestId, implementation);
        if (saltToCloseTime[salt] != 0) revert ProxyFactory__ContestIsAlreadyRegistered();
        saltToCloseTime[salt] = closeTime;
        emit SetContest(organizer, contestId, closeTime, implementation);
    }

    /**
     * @notice deploy proxy contract and distribute winner's prize
     * @dev the caller can only control his own contest
     * @param contestId The contest id
     * @param implementation The implementation address
     * @param data The prize distribution data
     * @return The proxy address
     */
    function deployProxyAndDistribute(bytes32 contestId, address implementation, bytes calldata data)
        public
        returns (address)
    {
        bytes32 salt = _calculateSalt(msg.sender, contestId, implementation);
        if (saltToCloseTime[salt] == 0) revert ProxyFactory__ContestIsNotRegistered();
        // can set close time to current time and end it immediately if organizer wish
        if (saltToCloseTime[salt] > block.timestamp) revert ProxyFactory__ContestIsNotClosed();
        address proxy = _deployProxy(msg.sender, contestId, implementation);
        _distribute(proxy, data);
        return proxy;
    }

    /**
     * @notice deploy proxy contract and distribute prize on behalf of organizer
     * @dev the caller can only control his own contest
     * @dev It uess EIP712 to verify the signature to avoid replay attacks
     * @dev front run is allowed because it will only help the tx sender
     * @param organizer The organizer of the contest
     * @param contestId The contest id
     * @param implementation The implementation address
     * @param signature The signature from organizer
     * @param data The prize distribution data
     * @return proxy The proxy address
     */
    function deployProxyAndDistributeBySignature(
        address organizer,
        bytes32 contestId,
        address implementation,
        bytes calldata signature,
        bytes calldata data
    ) public returns (address) {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(contestId, data)));
        if (ECDSA.recover(digest, signature) != organizer) revert ProxyFactory__InvalidSignature();
        bytes32 salt = _calculateSalt(organizer, contestId, implementation);
        if (saltToCloseTime[salt] == 0) revert ProxyFactory__ContestIsNotRegistered();
        if (saltToCloseTime[salt] > block.timestamp) revert ProxyFactory__ContestIsNotClosed();
        address proxy = _deployProxy(organizer, contestId, implementation);
        _distribute(proxy, data);
        return proxy;
    }

    /**
     * @notice deploy proxy contract and distribute prize on behalf of organizer by owner
     * @notice This can only be called after contest is expired
     * @dev the caller must be owner
     * @param organizer The organizer of the contest
     * @param contestId The contest id
     * @param implementation The implementation address
     * @param data The prize distribution data
     * @return proxy The proxy address
     */
    function deployProxyAndDistributeByOwner(
        address organizer,
        bytes32 contestId,
        address implementation,
        bytes calldata data
    ) public onlyOwner returns (address) {
        bytes32 salt = _calculateSalt(organizer, contestId, implementation);
        if (saltToCloseTime[salt] == 0) revert ProxyFactory__ContestIsNotRegistered();
        if (saltToCloseTime[salt] + EXPIRATION_TIME > block.timestamp) revert ProxyFactory__ContestIsNotExpired();
        // require(saltToCloseTime[salt] == 0, "Contest is not registered");
        // require(saltToCloseTime[salt] < block.timestamp + EXPIRATION_TIME, "Contest is not expired");
        address proxy = _deployProxy(organizer, contestId, implementation);
        _distribute(proxy, data);
        return proxy;
    }

    /**
     * @notice Owner can rescue funds if token is stuck after the deployment and contest is over for a while
     * @dev only owner can call this function and it is supposed not to be called often
     * @dev fee sent to stadium address is included in the logic contract
     * @param proxy The proxy address
     * @param organizer The contest organizer
     * @param contestId The contest id
     * @param implementation The implementation address
     * @param data The prize distribution calling data
     */
    function distributeByOwner(
        address proxy,
        address organizer,
        bytes32 contestId,
        address implementation,
        bytes calldata data
    ) public onlyOwner {
        if (proxy == address(0)) revert ProxyFactory__ProxyAddressCannotBeZero();
        bytes32 salt = _calculateSalt(organizer, contestId, implementation);
        if (saltToCloseTime[salt] == 0) revert ProxyFactory__ContestIsNotRegistered();
        // distribute only when it exists and expired
        if (saltToCloseTime[salt] + EXPIRATION_TIME > block.timestamp) revert ProxyFactory__ContestIsNotExpired();
        _distribute(proxy, data);
    }

    /// @notice This address can be used to send ERC20 tokens before deployment of proxy
    /// @dev Calculate the proxy address using salt and implementation address
    /// @param salt The salt
    /// @param implementation The implementation address
    /// @return proxy The calculated proxy address
    function getProxyAddress(bytes32 salt, address implementation) public view returns (address proxy) {
        bytes memory code = abi.encodePacked(type(Proxy).creationCode, uint256(uint160(implementation)));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(code)));
        proxy = address(uint160(uint256(hash)));
    }

    ///////////////////////////////////
    /////// Internal functions ////////
    ///////////////////////////////////
    /// @dev Deploy proxy and return the proxy address
    /// @dev This is an internal function
    /// @param organizer The contest organizer
    /// @param contestId The contest id
    /// @param implementation The implementation address
    function _deployProxy(address organizer, bytes32 contestId, address implementation) internal returns (address) {
        bytes32 salt = _calculateSalt(organizer, contestId, implementation);
        address proxy = address(new Proxy{salt: salt}(implementation));
        return proxy;
    }

    /// @dev The internal function to be used to call proxy to distribute prizes to the winners
    /// @dev the data passed in should be the calling data of the distributing logic
    /// @param proxy The proxy address
    /// @param data The prize distribution data
    function _distribute(address proxy, bytes calldata data) internal {
        (bool success,) = proxy.call(data);
        if (!success) revert ProxyFactory__DelegateCallFailed();
        emit Distributed(proxy, data);
    }

    /// @dev Calculate salt using contest organizer address and contestId, implementation address
    /// @dev This is an internal function
    /// @param organizer The contest organizer
    /// @param contestId The contest id
    /// @param implementation The implementation address
    function _calculateSalt(address organizer, bytes32 contestId, address implementation)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(organizer, contestId, implementation));
    }
}
