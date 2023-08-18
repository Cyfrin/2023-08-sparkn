// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {MockERC20} from "../mock/MockERC20.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ProxyFactory} from "../../src/ProxyFactory.sol";
import {Proxy} from "../../src/Proxy.sol";
import {Distributor} from "../../src/Distributor.sol";
import {HelperContract} from "../integration/HelperContract.t.sol";

contract FuzzTestProxyFactory is StdCheats, HelperContract {
    bytes32 constant SOMEID = keccak256(abi.encode("Jason", "001"));

    function setUp() public {
        // set up balances of each token belongs to each user
        if (block.chainid == 31337) {
            // deal ether
            vm.deal(factoryAdmin, STARTING_USER_BALANCE);
            vm.deal(sponsor, SMALL_STARTING_USER_BALANCE);
            vm.deal(organizer, SMALL_STARTING_USER_BALANCE);
            vm.deal(user1, SMALL_STARTING_USER_BALANCE);
            vm.deal(user2, SMALL_STARTING_USER_BALANCE);
            vm.deal(user3, SMALL_STARTING_USER_BALANCE);
            vm.deal(TEST_SIGNER, SMALL_STARTING_USER_BALANCE);
            // mint erc20 token
            vm.startPrank(tokenMinter);
            MockERC20(jpycv1Address).mint(sponsor, 100_000 ether); // 100k JPYCv1
            MockERC20(jpycv2Address).mint(sponsor, 300_000 ether); // 300k JPYCv2
            MockERC20(usdcAddress).mint(sponsor, 10_000 ether); // 10k USDC
            MockERC20(jpycv1Address).mint(organizer, 100_000 ether); // 100k JPYCv1
            MockERC20(jpycv2Address).mint(organizer, 300_000 ether); // 300k JPYCv2
            MockERC20(usdcAddress).mint(organizer, 10_000 ether); // 10k USDC
            MockERC20(jpycv1Address).mint(TEST_SIGNER, 100_000 ether); // 100k JPYCv1
            MockERC20(jpycv2Address).mint(TEST_SIGNER, 300_000 ether); // 300k JPYCv2
            MockERC20(usdcAddress).mint(TEST_SIGNER, 10_000 ether); // 10k USDC
            vm.stopPrank();
        }

        // labels
        vm.label(organizer, "organizer");
        vm.label(sponsor, "sponsor");
        vm.label(supporter, "supporter");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(user3, "user3");
    }

    function testSetupContractsExist() public {
        // addresses are not zero
        assertTrue(jpycv1Address != address(0));
        assertTrue(jpycv2Address != address(0));
        assertTrue(usdcAddress != address(0));
        assertTrue(address(proxyFactory) != address(0));
        assertTrue(address(distributor) != address(0));
    }

    function testFuzzSetupNonProxyFactoryIsWhitelisted(address randomAddr) public {
        // exclude whitelisted tokens
        vm.assume(randomAddr != address(jpycv1Address));
        vm.assume(randomAddr != address(jpycv2Address));
        vm.assume(randomAddr != address(usdcAddress));
        // check unwhitelisted address
        assertFalse(proxyFactory.whitelistedTokens(randomAddr));
    }

    ////////////////
    // setContest //
    ////////////////
    function testFuzzOwnerCanSetContestForAnyone(address randomUsr) public {
        vm.assume(randomUsr != address(0));
        bytes32 randomId = keccak256(abi.encode("Jim", "001"));
        vm.startPrank(factoryAdmin);
        proxyFactory.setContest(randomUsr, randomId, block.timestamp + 1 days, address(distributor));
        vm.stopPrank();
    }

    function testFuzzOwnerCanSetContestForAnyCloseTimeInRange(uint16 randomTime) public {
        uint256 randomTime_ = bound(randomTime, block.timestamp, block.timestamp + 28 days);
        bytes32 randomId = keccak256(abi.encode("Jim", "001"));

        vm.startPrank(factoryAdmin);
        proxyFactory.setContest(organizer, randomId, randomTime_, address(distributor));
        vm.stopPrank();
        bytes32 salt_ = keccak256(abi.encode(organizer, randomId, address(distributor)));
        assertTrue(proxyFactory.saltToCloseTime(salt_) == randomTime_);
    }

    function testFuzzAnyNonOwnerCannotSetContest(address randomUsr) public {
        vm.assume(randomUsr != address(0));
        vm.assume(randomUsr != factoryAdmin);
        bytes32 randomId = keccak256(abi.encode("Jim", "001"));
        vm.startPrank(randomUsr);
        vm.expectRevert("Ownable: caller is not the owner");
        uint256 inputTime = block.timestamp + 1 days;
        proxyFactory.setContest(randomUsr, randomId, inputTime, address(distributor));
        vm.stopPrank();
    }

    function testFuzzCanSetContestWithAnyImplementation(address randomImple) public {
        vm.assume(randomImple != address(0));
        bytes32 randomId = keccak256(abi.encode("Jim", "001"));
        vm.startPrank(factoryAdmin);
        uint256 inputTime = block.timestamp + 1 days;
        proxyFactory.setContest(organizer, randomId, inputTime, randomImple);
        vm.stopPrank();
        bytes32 salt_ = keccak256(abi.encode(organizer, randomId, randomImple));
        assertTrue(proxyFactory.saltToCloseTime(salt_) == inputTime);
    }

    function testFuzzCanSetContestWithAnyId(bytes32 randomId) public {
        vm.startPrank(factoryAdmin);
        uint256 inputTime = block.timestamp + 1 days;
        proxyFactory.setContest(organizer, randomId, inputTime, address(distributor));
        vm.stopPrank();
        bytes32 salt_ = keccak256(abi.encode(organizer, randomId, address(distributor)));
        assertTrue(proxyFactory.saltToCloseTime(salt_) == inputTime);
    }

    ///////////////////////
    // Modifier for test //
    ///////////////////////
    modifier setUpContestForJasonAndSentJpycv2Token(
        address _organizer,
        address token,
        uint256 amount,
        uint256 inputTime
    ) {
        vm.startPrank(factoryAdmin);
        bytes32 randomId = keccak256(abi.encode("Jason", "001"));
        proxyFactory.setContest(_organizer, randomId, inputTime, address(distributor));
        vm.stopPrank();
        bytes32 salt = keccak256(abi.encode(_organizer, randomId, address(distributor)));
        address proxyAddress = proxyFactory.getProxyAddress(salt, address(distributor));
        vm.startPrank(sponsor);
        MockERC20(token).transfer(proxyAddress, amount);
        vm.stopPrank();
        // console.log(MockERC20(jpycv2Address).balanceOf(proxyAddress));
        assertEq(MockERC20(token).balanceOf(proxyAddress), amount);
        _;
    }

    function createData(uint256 user1Percentage) public view returns (bytes memory data) {
        address[] memory winners = new address[](2);
        winners[0] = user1;
        winners[1] = user2;
        uint256[] memory percentages_ = new uint256[](2);
        percentages_[0] = user1Percentage;
        percentages_[1] = 9500 - user1Percentage;
        data = abi.encodeWithSelector(Distributor.distribute.selector, jpycv2Address, winners, percentages_, "");
    }

    function createDataToSendToAdmin() public view returns (bytes memory data) {
        address[] memory tokens_ = new address[](1);
        tokens_[0] = jpycv2Address;
        address[] memory winners = new address[](1);
        winners[0] = stadiumAddress;
        uint256[] memory percentages_ = new uint256[](1);
        percentages_[0] = 9500;
        data = abi.encodeWithSelector(Distributor.distribute.selector, jpycv2Address, winners, percentages_, "");
    }

    //////////////////////////////
    // deployProxyAndDistribute //
    //////////////////////////////
    // contest id set and prize token is sent to the proxy
    function testFuzzCalledWithContestIdNotExistThenRevert(bytes32 randomId)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 1000 ether, block.timestamp + 1 days)
    {
        // create data with wrong contestId
        vm.assume(randomId != keccak256(abi.encode("Jason", "001")));
        bytes memory data = createData(5000);

        // deploy proxy and distribute
        vm.warp(14 days);
        vm.startPrank(organizer);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.deployProxyAndDistribute(randomId, address(distributor), data);
        vm.stopPrank();
    }

    function testFuzzCloseTimeNotReachedThenRevert(uint16 randomTime) public {
        // set contest and send token to proxy
        vm.startPrank(factoryAdmin);
        bytes32 someId = keccak256(abi.encode("Jason", "001"));
        proxyFactory.setContest(organizer, someId, block.timestamp + 1 days, address(distributor));
        vm.stopPrank();
        bytes32 salt = keccak256(abi.encode(organizer, someId, address(distributor)));
        address proxyAddress = proxyFactory.getProxyAddress(salt, address(distributor));
        // send token to proxy
        vm.startPrank(sponsor);
        MockERC20(jpycv2Address).transfer(proxyAddress, 10000 ether);
        vm.stopPrank();
        assertEq(MockERC20(jpycv2Address).balanceOf(proxyAddress), 10000 ether);

        // set bounded random time
        uint256 randomTime_ = bound(randomTime, block.timestamp, block.timestamp + 1 days - 1 seconds);
        // create a data for calling distribute
        bytes memory data = createData(5000);

        // simulating time elapsed
        vm.warp(randomTime_);
        // deploy proxy and distribute but expect revertting
        vm.startPrank(organizer);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotClosed.selector);
        proxyFactory.deployProxyAndDistribute(someId, address(distributor), data);
        vm.stopPrank();
    }

    // create data with wrong implementation address
    function testFuzzCalledWithWrongImplementationAddrThenRevert(address randomImple)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 1000 ether, block.timestamp + 1 days)
    {
        // set contest and send token to proxy
        vm.assume(randomImple != address(distributor));
        vm.assume(randomImple != address(0));
        bytes32 someId = keccak256(abi.encode("Jason", "001"));
        // create data to send to proxy to distribute
        bytes memory data = createData(5000);
        // simulating time elapsed
        vm.warp(2 days);
        // deploy proxy and distribute but expect revertting
        vm.startPrank(organizer);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.deployProxyAndDistribute(someId, address(randomImple), data);
        vm.stopPrank();
    }

    function testFuzzCalledWithNonOrganizerThenRevert(address randomUsr)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 1000 ether, block.timestamp + 1 days)
    {
        vm.assume(randomUsr != organizer);
        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);
        // console.log(proxyFactory.saltToCloseTime(keccak256(abi.encode(organizer, randomId_, usdcAddress))));

        vm.warp(9 days);
        vm.startPrank(randomUsr);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.deployProxyAndDistribute(randomId_, address(distributor), data);
        vm.stopPrank();
    }

    function testFuzzSucceedsWhenConditionsMetWithRandomPercetages(uint256 randomNum)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        // before
        assertEq(MockERC20(jpycv2Address).balanceOf(user1), 0 ether);
        assertEq(MockERC20(jpycv2Address).balanceOf(user2), 0 ether);
        assertEq(MockERC20(jpycv2Address).balanceOf(stadiumAddress), 0 ether);
        // bounded random number
        uint256 randomNum_ = bound(randomNum, 0, 9500);
        // vm.assume(randomNum <= 9500);
        bytes32 someId = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(randomNum_);
        vm.warp(2 days);
        vm.startPrank(organizer);
        proxyFactory.deployProxyAndDistribute(someId, address(distributor), data);
        vm.stopPrank();

        // after
        assertEq(MockERC20(jpycv2Address).balanceOf(user1), randomNum_ * 1e18);
        assertEq(MockERC20(jpycv2Address).balanceOf(user2), 9500 * 1e18 - randomNum_ * 1e18);
        assertEq(MockERC20(jpycv2Address).balanceOf(stadiumAddress), 500 ether);
    }

    ///////////////////////////////////////
    /// deployProxyAndDistributeByOwner ///
    ///////////////////////////////////////
    function testFuzzRevertsIfCalledByNonOwnerTodeployProxy(address randomUsr)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        vm.assume(randomUsr != factoryAdmin);
        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);

        vm.warp(8 days);
        vm.startPrank(randomUsr);
        vm.expectRevert("Ownable: caller is not the owner");
        proxyFactory.deployProxyAndDistributeByOwner(organizer, randomId_, address(distributor), data);
        vm.stopPrank();
    }

    function testFuzzRevertsIfCalledWithWrongContestId(bytes32 randomId_)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        vm.assume(randomId_ != keccak256(abi.encode("Jason", "001")));
        bytes memory data = createData(5000);

        vm.warp(9 days);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.deployProxyAndDistributeByOwner(organizer, randomId_, address(distributor), data);
        vm.stopPrank();
    }

    function testFuzzRevertsIfCalledWithWrongDistributor(address randomDistributor)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        vm.assume(randomDistributor != address(distributor));
        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);

        vm.warp(9 days);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.deployProxyAndDistributeByOwner(organizer, randomId_, randomDistributor, data);
        vm.stopPrank();
    }

    function testFuzzRevertsIfContestIsNotExpired(uint32 randomTime)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        vm.assume(randomTime < 8 days);
        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);

        vm.warp(randomTime);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotExpired.selector);
        proxyFactory.deployProxyAndDistributeByOwner(organizer, randomId_, address(distributor), data);
        vm.stopPrank();
    }

    function testFuzzRevertsIfCalledWithWrongImplementation(address randomImple)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        vm.assume(randomImple != address(distributor));
        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);

        vm.warp(16 days);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.deployProxyAndDistributeByOwner(organizer, randomId_, address(randomImple), data);
        vm.stopPrank();
    }

    function testFuzzSucceedsIfAllConditionsMetWithRandomPercentages(uint256 randomNum)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        // before
        assertEq(MockERC20(jpycv2Address).balanceOf(user1), 0 ether);
        assertEq(MockERC20(jpycv2Address).balanceOf(user2), 0 ether);
        assertEq(MockERC20(jpycv2Address).balanceOf(stadiumAddress), 0 ether);
        // bounded random number
        uint256 randomNum_ = bound(randomNum, 0, 9500);

        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(randomNum_);

        vm.warp(8.01 days);
        vm.startPrank(factoryAdmin);
        proxyFactory.deployProxyAndDistributeByOwner(organizer, randomId_, address(distributor), data);
        vm.stopPrank();

        // after
        assertEq(MockERC20(jpycv2Address).balanceOf(user1), randomNum_ * 1e18);
        assertEq(MockERC20(jpycv2Address).balanceOf(user2), (9500 - randomNum_) * 1e18);
        assertEq(MockERC20(jpycv2Address).balanceOf(stadiumAddress), 500 ether);
    }

    /////////////////////////
    /// distributeByOwner ///
    /////////////////////////
    function testFuzzRevertsIfContestIdIsNotRightDistributeByOwner(bytes32 randomId_)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        vm.assume(randomId_ != keccak256(abi.encode("Jason", "001")));
        bytes32 someId = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);

        vm.warp(8.01 days);
        vm.startPrank(organizer);
        address proxyAddress = proxyFactory.deployProxyAndDistribute(someId, address(distributor), data);
        vm.stopPrank();

        // sponsor send token to proxy by mistake
        vm.startPrank(sponsor);
        MockERC20(jpycv2Address).transfer(proxyAddress, 10000 ether);
        vm.stopPrank();
        bytes memory dataToSendToAdmin = createDataToSendToAdmin();

        // 15 days is the edge of close time, after that tx can go through
        vm.warp(16 days);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.distributeByOwner(proxyAddress, organizer, randomId_, address(distributor), dataToSendToAdmin);
        vm.stopPrank();
    }

    function testFuzzRevertsIfImplementationIsNotRightDistributeByOwner(address randomImple)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        // prepare for data
        bytes memory data = createData(5000);
        // set assuming
        vm.assume(randomImple != address(distributor));
        vm.assume(randomImple != address(0));

        // owner deploy and distribute
        vm.warp(9 days);
        vm.startPrank(organizer);
        address proxyAddress = proxyFactory.deployProxyAndDistribute(SOMEID, address(distributor), data);
        vm.stopPrank();

        // sponsor send token to proxy by mistake
        vm.startPrank(sponsor);
        MockERC20(jpycv2Address).transfer(proxyAddress, 10000 ether);
        vm.stopPrank();
        // create data to send the token to admin
        bytes memory dataToSendToAdmin = createDataToSendToAdmin();

        // 15 days is the edge of close time, after that tx can go through
        vm.warp(8.01 days);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.distributeByOwner(proxyAddress, organizer, SOMEID, randomImple, dataToSendToAdmin);
        vm.stopPrank();
    }

    function testFuzzRevertsIfOrganizerIsNotRightDistributeByOwner(address randomUsr)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        // prepare for data
        bytes memory data = createData(5000);

        // assume random user is not organizer or zero
        vm.assume(randomUsr != organizer);
        vm.assume(randomUsr != address(0));

        // owner deploy and distribute
        vm.warp(9 days);
        vm.startPrank(organizer);
        address proxyAddress = proxyFactory.deployProxyAndDistribute(SOMEID, address(distributor), data);
        vm.stopPrank();

        // sponsor send token to proxy by mistake
        vm.startPrank(sponsor);
        MockERC20(jpycv2Address).transfer(proxyAddress, 10000 ether);
        vm.stopPrank();
        // create data to send the token to admin
        bytes memory dataToSendToAdmin = createDataToSendToAdmin();

        // 15 days is the edge of close time, after that tx can go through
        vm.warp(8.01 days);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotRegistered.selector);
        proxyFactory.distributeByOwner(proxyAddress, randomUsr, SOMEID, address(distributor), dataToSendToAdmin);
        vm.stopPrank();
    }

    function testFuzzRevertsIfClosetimeIsNotReadyDistributeByOwner(uint256 randomTime)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        // prepare for data
        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);
        vm.assume(randomTime < 8 days);

        // owner deploy and distribute
        vm.warp(2 days);
        vm.startPrank(organizer);
        address proxyAddress = proxyFactory.deployProxyAndDistribute(randomId_, address(distributor), data);
        vm.stopPrank();

        // sponsor send token to proxy by mistake
        vm.startPrank(sponsor);
        MockERC20(jpycv2Address).transfer(proxyAddress, 10000 ether);
        vm.stopPrank();
        // create data to send the token to admin
        bytes memory dataToSendToAdmin = createDataToSendToAdmin();

        // 15 days is the edge of close time, after that tx can go through
        vm.warp(randomTime);
        vm.startPrank(factoryAdmin);
        vm.expectRevert(ProxyFactory.ProxyFactory__ContestIsNotExpired.selector);
        proxyFactory.distributeByOwner(proxyAddress, organizer, randomId_, address(distributor), dataToSendToAdmin);
        vm.stopPrank();
    }

    function testFuzzRevertsIfCalledByNonOwnerDistributeByOwner(address randomUsr)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        // prepare for data
        bytes32 randomId_ = keccak256(abi.encode("Jason", "001"));
        bytes memory data = createData(5000);
        vm.assume(randomUsr != factoryAdmin);
        vm.assume(randomUsr != address(0));

        // owner deploy and distribute
        vm.warp(16 days);
        vm.startPrank(factoryAdmin);
        address proxyAddress =
            proxyFactory.deployProxyAndDistributeByOwner(organizer, randomId_, address(distributor), data);
        vm.stopPrank();

        // sponsor send token to proxy by mistake
        vm.startPrank(sponsor);
        MockERC20(jpycv2Address).transfer(proxyAddress, 10000 ether);
        vm.stopPrank();
        // create data to send the token to admin
        bytes memory dataToSendToAdmin = createDataToSendToAdmin();

        vm.warp(16 days);
        vm.startPrank(randomUsr);
        vm.expectRevert("Ownable: caller is not the owner");
        proxyFactory.distributeByOwner(proxyAddress, organizer, randomId_, address(distributor), dataToSendToAdmin);
        vm.stopPrank();
    }

    function testFuzzSucceedIfAllConditionsMetDistributeByOwner(uint256 randomNum)
        public
        setUpContestForJasonAndSentJpycv2Token(organizer, jpycv2Address, 10000 ether, block.timestamp + 1 days)
    {
        // before
        assertEq(MockERC20(jpycv2Address).balanceOf(user1), 0 ether);
        assertEq(MockERC20(jpycv2Address).balanceOf(user2), 0 ether);
        assertEq(MockERC20(jpycv2Address).balanceOf(stadiumAddress), 0 ether);

        // assume randomNum is in range of 0 ~ 9500
        uint256 randomNum_ = bound(randomNum, 0, 9500);

        // prepare for data
        bytes32 salt_ = keccak256(abi.encode(organizer, SOMEID, address(distributor)));
        bytes memory data = createData(randomNum_);

        // calculate proxy address
        address calculatedProxyAddress = proxyFactory.getProxyAddress(salt_, address(distributor));

        // owner deploy and distribute
        vm.warp(16 days);
        vm.startPrank(factoryAdmin);
        address proxyAddress =
            proxyFactory.deployProxyAndDistributeByOwner(organizer, SOMEID, address(distributor), data);
        vm.stopPrank();
        assertEq(proxyAddress, calculatedProxyAddress);

        // sponsor send token to proxy by mistake
        vm.startPrank(sponsor);
        MockERC20(jpycv2Address).transfer(proxyAddress, 10000 ether);
        vm.stopPrank();

        bytes memory dataToSendToAdmin = createDataToSendToAdmin();
        vm.startPrank(factoryAdmin);
        proxyFactory.distributeByOwner(
            calculatedProxyAddress, organizer, SOMEID, address(distributor), dataToSendToAdmin
        );
        vm.stopPrank();

        // after
        assertEq(MockERC20(jpycv2Address).balanceOf(user1), randomNum_ * 1e18);
        assertEq(MockERC20(jpycv2Address).balanceOf(user2), (9500 - randomNum_) * 1e18);
        assertEq(MockERC20(jpycv2Address).balanceOf(stadiumAddress), 10500 ether);
        // stadiumAddress get 500 ether from sponsor and then get all the token sent from sponsor by mistake.
    }
}
