// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract cSphere is ERC20, AccessControl {
  bytes32 public constant GAME_ROLE = keccak256("GAME");

  constructor() ERC20("Casino Sphere", "cSphere") {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  modifier onlyAdmin() {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Admin restricted");
    _;
  }

  modifier onlyGame() {
    require(hasRole(GAME_ROLE, msg.sender), "Game restricted");
    _;
  }

  function addGame(address _gameAddress) public onlyAdmin {
    grantRole(GAME_ROLE, _gameAddress);
  }

  function mint(address _account, uint256 _amount) public onlyGame {
    _mint(_account, _amount);
  }

  function _transfer(address sender, address recipient, uint256 amount) internal override {
    require(hasRole(GAME_ROLE, sender) || hasRole(GAME_ROLE, recipient), "non transferable token between users");
    return super._transfer(sender, recipient, amount);
  }

  event IAmHere(address sender);
}