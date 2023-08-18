// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../test/mock/MockERC20.sol";

// This contract script is to deploy the contracts on different networks and can be used for testing purposes
contract HelperConfig is Script {
    address public tokenMinter = makeAddr("tokenMinter");
    address public minter = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    struct NetworkConfig {
        // deployer's private key
        // address[] tokensToWhitelist;
        address jpycv1Address;
        address jpycv2Address;
        address usdcAddress;
        address usdtAddress;
        uint256 deployerKey;
    }

    // anvil's default private key
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            // activeNetworkConfig = getSepoliaEthereumConfig();
        } else if (block.chainid == 137) {
            activeNetworkConfig = getPolygonConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthereumConfig() public view returns (NetworkConfig memory) {
        // address[2] memory arr = [makeAddr("weth"), makeAddr("wbtc")];
        // return NetworkConfig({
        // tokensToWhitelist: arr,
        // deployerKey: vm.envUint("PRIVATE_KEY")
        // });
    }

    function getPolygonConfig() public view returns (NetworkConfig memory) {
        // real addresses
        address[] memory arr = new address[](3);
        arr[0] = 0x431D5dfF03120AFA4bDf332c61A6e1766eF37BDB; // jpyc v2 on polygon
        arr[1] = 0x2370f9d504c7a6E775bf6E14B3F12846b594cD53; // jpyc v1 on polygon
        arr[2] = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // usdc on polygon
        // arr[3] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F; // usdt on polygon

        return NetworkConfig({
            jpycv1Address: arr[0],
            jpycv2Address: arr[1],
            usdcAddress: arr[2],
            usdtAddress: address(0),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.jpycv1Address != address(0)) {
            return activeNetworkConfig;
        }

        // deploy contracts
        vm.startBroadcast();

        MockERC20 jpycV2Mock = new MockERC20(
            "JPY Coin V2",
            "JPYCv2"
        );
        MockERC20 jpycv1Mock = new MockERC20(
            "JPY Coin V1",
            "JPYCv1"
        );
        MockERC20 usdcMock = new MockERC20(
            "USD Coin",
            "USDC"
        );
        MockERC20 usdtMock = new MockERC20(
            "Tether",
            "USDT"
        );

        vm.stopBroadcast();
        // console.log('msgsender: ', msg.sender);
        // console.log('tokenMinter: ', tokenMinter);
        // console.log('realMinter: ', jpycV2Mock.owner());
        vm.startPrank(minter);
        jpycV2Mock.transferOwnership(tokenMinter);
        jpycv1Mock.transferOwnership(tokenMinter);
        usdcMock.transferOwnership(tokenMinter);
        vm.stopPrank();

        return NetworkConfig({
            jpycv1Address: address(jpycV2Mock),
            jpycv2Address: address(jpycv1Mock),
            usdcAddress: address(usdcMock),
            usdtAddress: address(usdtMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
