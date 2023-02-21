// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {MerkleProofLib} from "solmate/utils/MerkleProofLib.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {ICryptoPunksMarket} from "./interfaces/ICryptoPunksMarket.sol";

contract PunkBidMarketV1 is Owned {
  address public immutable WETH;

  address public immutable CRYPTOPUNKS_MARKET;

  uint256 public immutable FEE = 0.25 ether;

  struct Bid {
    address bidder;
    uint96 expiration;
    uint256 weiAmount;
    bytes32 itemsChecksum;
  }

  struct BidUpdate {
    uint256 bidId;
    uint256 weiAmount;
  }

  mapping(uint256 => Bid) public bids;

  uint256 public nextBidId = 1;

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

  constructor(address _WETH, address _CRYPTOPUNKS_MARKET) Owned(msg.sender) {
    WETH = _WETH;
    CRYPTOPUNKS_MARKET = _CRYPTOPUNKS_MARKET;
  }

  receive() external payable {}

  function enterBid(
    uint256 weiAmount,
    uint96 expiration,
    bytes32 itemsChecksum,
    string calldata name,
    bytes calldata cartMetadata
  ) external {
    bids[nextBidId] = Bid(msg.sender, expiration, weiAmount, itemsChecksum);
    emit BidEntered(
      nextBidId++,
      msg.sender,
      expiration,
      weiAmount,
      name,
      itemsChecksum,
      cartMetadata
    );
  }

  function updateBids(BidUpdate[] calldata updates) external {
    uint len = updates.length;

    for (uint i = 0; i < len; ) {
      BidUpdate calldata update = updates[i];
      require(bids[update.bidId].bidder == msg.sender);
      bids[update.bidId].weiAmount = update.weiAmount;
      emit BidUpdated(update.bidId, update.weiAmount);

      unchecked {
        ++i;
      }
    }
  }

  function cancelBids(uint256[] calldata bidIds) external {
    uint len = bidIds.length;

    for (uint i = 0; i < len; ) {
      uint256 bidId = bidIds[i];
      require(bids[bidId].bidder == msg.sender);
      delete bids[bidId];
      emit BidCancelled(bidId);

      unchecked {
        ++i;
      }
    }
  }

  function acceptBid(
    uint256 punkIndex,
    uint256 minWeiAmount,
    uint256 bidId,
    bytes32[] calldata proof
  ) external {
    ICryptoPunksMarket.Offer memory offer = ICryptoPunksMarket(
      CRYPTOPUNKS_MARKET
    ).punksOfferedForSale(punkIndex);
    if (!offer.isForSale || msg.sender != offer.seller || offer.minValue > 0)
      revert();

    Bid memory bid = bids[bidId];
    if (
      bid.weiAmount < minWeiAmount ||
      bid.expiration < uint96(block.timestamp) ||
      !MerkleProofLib.verify(
        proof,
        bid.itemsChecksum,
        keccak256(abi.encodePacked(punkIndex))
      )
    ) revert();

    IWETH9(WETH).transferFrom(bid.bidder, address(this), bid.weiAmount);
    IWETH9(WETH).withdraw(bid.weiAmount);
    ICryptoPunksMarket(CRYPTOPUNKS_MARKET).buyPunk(punkIndex);
    ICryptoPunksMarket(CRYPTOPUNKS_MARKET).transferPunk(bid.bidder, punkIndex);

    emit BidFilled(bidId, punkIndex, offer.seller, bid.bidder, bid.weiAmount);
    delete bids[bidId];

    (bool sent, ) = offer.seller.call{value: bid.weiAmount - FEE}(new bytes(0));
    require(sent);
  }

  function withdraw() external onlyOwner {
    (bool sent, ) = msg.sender.call{value: address(this).balance}(new bytes(0));
    require(sent);
  }
}
