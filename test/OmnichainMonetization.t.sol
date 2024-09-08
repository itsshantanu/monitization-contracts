// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/OmnichainMonetization.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

contract OmnichainMonetizationTest is Test {
    OmnichainMonetization public omnichainMonetization;
    MockERC20 public paymentToken;
    address public owner;
    address public addr1;
    address public addr2;

    function setUp() public {
        owner = address(this);
        addr1 = address(0x1);
        addr2 = address(0x2);

        // Debugging statements
        emit log("Setting up test environment");

        paymentToken = new MockERC20("Mock Token", "MTK", 1000 ether);
        emit log("MockERC20 deployed");

        omnichainMonetization = new OmnichainMonetization(
            "OmnichainNFT",
            "ONFT",
            address(paymentToken),
            5, // Platform fee percentage
            owner, // LayerZero endpoint
            owner  // Delegate
        );
        emit log("OmnichainMonetization deployed");

        // Distribute tokens
        paymentToken.transfer(addr1, 100 ether);
        paymentToken.transfer(addr2, 100 ether);
        emit log("Tokens distributed");
    }

    function testUploadContent() public {
        vm.prank(addr1);
        omnichainMonetization.uploadContent(
            "QmHash",
            1 ether,
            10,
            false,
            0
        );

        (address creator, string memory contentHash, uint256 price, uint256 royaltyPercentage, bool isSubscription, uint256 subscriptionDuration) = omnichainMonetization.getContentDetails(1);
        assertEq(creator, addr1);
        assertEq(contentHash, "QmHash");
        assertEq(price, 1 ether);
        assertEq(royaltyPercentage, 10);
        assertEq(isSubscription, false);
        assertEq(subscriptionDuration, 0);
    }


    function testPurchaseContent() public {
        vm.prank(addr1);
        omnichainMonetization.uploadContent(
            "QmHash",
            1 ether,
            10,
            false,
            0
        );

        vm.prank(addr2);
        paymentToken.approve(address(omnichainMonetization), 1 ether);

        vm.prank(addr2);
        omnichainMonetization.purchaseContent(1);

        assertEq(omnichainMonetization.ownerOf(1), addr2);
    }

    function testHandleSubscriptions() public {
        vm.prank(addr1);
        omnichainMonetization.uploadContent(
            "QmHash",
            1 ether,
            10,
            true,
            3600 // 1 hour
        );

        vm.prank(addr2);
        paymentToken.approve(address(omnichainMonetization), 1 ether);

        vm.prank(addr2);
        omnichainMonetization.purchaseContent(1);

        uint256 expiry = omnichainMonetization.subscriptionExpiry(1, addr2);
        assertGt(expiry, block.timestamp);
    }

    function testWithdrawPlatformFees() public {
        vm.prank(addr1);
        omnichainMonetization.uploadContent(
            "QmHash",
            1 ether,
            10,
            false,
            0
        );

        vm.prank(addr2);
        paymentToken.approve(address(omnichainMonetization), 1 ether);

        vm.prank(addr2);
        omnichainMonetization.purchaseContent(1);

        uint256 initialBalance = paymentToken.balanceOf(owner);
        omnichainMonetization.withdrawPlatformFees();
        uint256 finalBalance = paymentToken.balanceOf(owner);

        assertGt(finalBalance, initialBalance);
    }
}