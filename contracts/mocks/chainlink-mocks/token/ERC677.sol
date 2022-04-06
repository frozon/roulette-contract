// SPDX-License-Identifier: GPL-3.0
// TODO: Remove this mock once Chainlink supports v0.8 mocks
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ERC677 is IERC20 {
  function transferAndCall(address to, uint value, bytes memory data) public virtual returns (bool success);

  event Transfer(address indexed from, address indexed to, uint value, bytes data);
}
