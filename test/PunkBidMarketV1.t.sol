// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {GeneratedMerkleProofs} from "./GeneratedMerkleProofs.sol";
import {PunkBidMarketV1} from "../src/PunkBidMarketV1.sol";
import {ICryptoPunksMarket} from "../src/interfaces/ICryptoPunksMarket.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";

contract PunkBidMarketV1Test is Test, GeneratedMerkleProofs {
  address immutable cryptopunksMarket = vm.envAddress("CRYPTOPUNKS_ADDRESS");
  address immutable weth = vm.envAddress("WETH_ADDRESS");
  uint96 constant expiration = 50_000;
  string constant bidName = "Clean Hoodies";
  bytes constant cartMetadata = hex"01";

  address immutable holder = vm.envAddress("MAINNET_PUNK_OWNER");
  address bidder = makeAddr("bidder");

  PunkBidMarketV1 public market;

  event BidEntered(
    uint256 indexed bidId,
    address indexed bidder,
    uint96 expiration,
    uint256 weiAmount,
    string name,
    bytes32 itemsChecksum,
    bytes cartMetadata
  );
  event BidUpdated(uint256 indexed bidId, uint256 weiAmount);
  event BidCancelled(uint256 indexed bidId);
  event BidFilled(
    uint256 indexed bidId,
    uint256 punkIndex,
    address seller,
    address buyer,
    uint256 weiAmount
  );

  receive() external payable {}

  function setUp() public {
    market = new PunkBidMarketV1(weth, cryptopunksMarket);
  }

  function _enterBids() internal returns (uint256[] memory) {
    uint256[] memory bidIds = new uint256[](2);

    bidIds[0] = market.nextBidId();
    market.enterBid(1 ether, expiration, itemsChecksum, bidName, cartMetadata);
    bidIds[1] = market.nextBidId();
    market.enterBid(1 ether, expiration, itemsChecksum, bidName, cartMetadata);
    return bidIds;
  }

  function _enterBidHoax(
    uint256 depositValue,
    uint256 approvalValue,
    uint256 bidValue,
    uint96 exp
  ) internal returns (uint256 bidId) {
    startHoax(bidder);
    IWETH9(weth).deposit{value: depositValue}();
    IWETH9(weth).approve(address(market), approvalValue);
    bidId = market.nextBidId();
    market.enterBid(bidValue, exp, itemsChecksum, bidName, cartMetadata);
    vm.stopPrank();
  }

  function testEnterBid() public {
    vm.expectEmit(true, true, false, true);
    emit BidEntered(1, address(this), expiration, 1 ether, bidName, itemsChecksum, cartMetadata);
    market.enterBid(1 ether, expiration, itemsChecksum, bidName, cartMetadata);

    (
      address actualBidder,
      uint96 actualExpiration,
      uint256 weiAmount,
      bytes32 actualitemsChecksum
    ) = market.bids(1);

    assertEq(actualBidder, address(this));
    assertEq(weiAmount, 1 ether);
    assertEq(actualExpiration, expiration);
    assertEq(actualitemsChecksum, itemsChecksum);
  }

  function testUpdateBids() public {
    uint256[] memory bidIds = _enterBids();

    vm.expectEmit(true, false, false, true);
    emit BidUpdated(bidIds[0], 2 ether);
    vm.expectEmit(true, false, false, true);
    emit BidUpdated(bidIds[1], 3 ether);

    PunkBidMarketV1.BidUpdate[]
      memory updates = new PunkBidMarketV1.BidUpdate[](2);
    updates[0] = PunkBidMarketV1.BidUpdate(bidIds[0], 2 ether);
    updates[1] = PunkBidMarketV1.BidUpdate(bidIds[1], 3 ether);

    market.updateBids(updates);

    (, , uint256 weiAmount1, ) = market.bids(bidIds[0]);
    assertEq(weiAmount1, 2 ether);
    (, , uint256 weiAmount2, ) = market.bids(bidIds[1]);
    assertEq(weiAmount2, 3 ether);
  }

  function testCancelBids() public {
    uint256[] memory bidIds = _enterBids();

    vm.expectEmit(true, false, false, true);
    emit BidCancelled(bidIds[0]);
    vm.expectEmit(true, false, false, true);
    emit BidCancelled(bidIds[1]);

    market.cancelBids(bidIds);

    (address bidder1, , , ) = market.bids(bidIds[0]);
    assertEq(bidder1, address(0));
    (address bidder2, , , ) = market.bids(bidIds[1]);
    assertEq(bidder2, address(0));
  }

  function testAcceptValidBid() public {
    uint256 bidId = _enterBidHoax(5 ether, 5 ether, 5 ether, 100_000_000_000);
    vm.startPrank(holder);
    deal(holder, 0);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(280, 0);
    vm.expectEmit(true, false, false, true);
    emit BidFilled(bidId, 280, holder, bidder, 5 ether);
    market.acceptBid(280, 5 ether, bidId, proof280);
    vm.stopPrank();

    assertEq(
      ICryptoPunksMarket(cryptopunksMarket).punkIndexToAddress(280),
      bidder
    );
    assertEq(holder.balance, 5 ether - market.FEE());
    assertEq(IWETH9(weth).balanceOf(bidder), 0);
    assertEq(address(market).balance, market.FEE());
    (address actualBidder, , , ) = market.bids(bidId);
    assertEq(actualBidder, address(0));
  }

  function testAcceptBidOnUnlistedPunk() public {
    uint256 bidId = _enterBidHoax(5 ether, 5 ether, 5 ether, 100_000_000_000);
    vm.startPrank(holder);
    vm.expectRevert();
    market.acceptBid(283, 5 ether, bidId, proof283);
    vm.stopPrank();
  }

  function testAcceptBidFromImpersonator() public {
    uint256 punkIndex = 742;
    uint256 bidId = _enterBidHoax(5 ether, 5 ether, 5 ether, 100_000_000_000);
    vm.prank(holder);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(punkIndex, 0);
    vm.expectRevert();
    market.acceptBid(punkIndex, 5 ether, bidId, proof742);
  }

  function testAcceptBidOnNonZeroOffer() public {
    uint256 punkIndex = 944;
    uint256 bidId = _enterBidHoax(5 ether, 5 ether, 5 ether, 100_000_000_000);
    vm.startPrank(holder);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(punkIndex, 1);
    vm.expectRevert();
    market.acceptBid(punkIndex, 5 ether, bidId, proof944);
    vm.stopPrank();
  }

  function testAcceptBidAbovePrice() public {
    uint256 punkIndex = 1211;
    uint256 bidId = _enterBidHoax(5 ether, 5 ether, 5 ether, 100_000_000_000);
    vm.startPrank(holder);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(punkIndex, 0);
    vm.expectRevert();
    market.acceptBid(punkIndex, 6 ether, bidId, proof1211);
    vm.stopPrank();
  }

  function testAcceptBidWithInsufficientBalance() public {
    uint256 punkIndex = 1231;
    uint256 bidId = _enterBidHoax(5 ether, 6 ether, 6 ether, 100_000_000_000);
    vm.startPrank(holder);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(punkIndex, 0);
    vm.expectRevert();
    market.acceptBid(punkIndex, 6 ether, bidId, proof1231);
    vm.stopPrank();
  }

  function testAcceptBidWithInsufficientAllowance() public {
    uint256 punkIndex = 1259;
    uint256 bidId = _enterBidHoax(5 ether, 4 ether, 5 ether, 100_000_000_000);
    vm.startPrank(holder);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(punkIndex, 0);
    vm.expectRevert();
    market.acceptBid(punkIndex, 5 ether, bidId, proof1259);
    vm.stopPrank();
  }

  function testAcceptExpiredBid() public {
    uint256 punkIndex = 1274;
    uint256 bidId = _enterBidHoax(5 ether, 5 ether, 5 ether, 0);
    vm.startPrank(holder);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(punkIndex, 0);
    vm.expectRevert();
    market.acceptBid(punkIndex, 5 ether, bidId, proof1274);
    vm.stopPrank();
  }

  function testAcceptBidWithInvalidProof() public {
    uint256 punkIndex = 1380;
    uint256 bidId = _enterBidHoax(5 ether, 5 ether, 5 ether, 100_000_000_000);
    vm.startPrank(holder);
    ICryptoPunksMarket(cryptopunksMarket).offerPunkForSale(punkIndex, 0);
    vm.expectRevert();
    market.acceptBid(punkIndex, 5 ether, bidId, proof1380);
    vm.stopPrank();
  }

  function testWithdrawFromOwner(uint96 amount) public {
    payable(address(market)).transfer(amount);
    uint256 preBalance = address(this).balance;
    market.withdraw();
    uint256 postBalance = address(this).balance;
    assertEq(preBalance + amount, postBalance);
  }

  function testWithdrawFromImpersonator() public {
    vm.prank(bidder);
    vm.expectRevert();
    market.withdraw();
  }
}
