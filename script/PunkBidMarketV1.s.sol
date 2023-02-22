// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "../src/PunkBidMarketV1.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";
import {ICryptoPunksMarket} from "../src/interfaces/ICryptoPunksMarket.sol";

contract Testnet is Script {
  address immutable cryptopunksMarket = vm.envAddress("CRYPTOPUNKS_ADDRESS");
  address immutable weth = vm.envAddress("WETH_ADDRESS");

  function setUp() public {}

  function run() public {
    vm.broadcast(vm.envUint("TESTNET_DEPLOYER"));
    new PunkBidMarketV1(weth, cryptopunksMarket);

    vm.broadcast(vm.envUint("TESTNET_BIDDER"));
    IWETH9(weth).deposit{value: 100 ether}();
  }
}
