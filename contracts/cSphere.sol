// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract cSphere is ERC20, AccessControl {
  bytes32 public constant GAME_ROLE = keccak256("GAME");

  address constant DEAD = 0x000000000000000000000000000000000000dEaD;
  mapping(address => bool) private games;
  address[] private gamesAddress;

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
    require(!games[_gameAddress], "Game already present");
    games[_gameAddress] = true;
    gamesAddress.push(_gameAddress);
    grantRole(GAME_ROLE, _gameAddress);
  }

  function removeGame(address _gameAddress) public onlyAdmin {
    require(games[_gameAddress], "Unknow game");
    games[_gameAddress] = false;

    bool found = false;
    for(uint256 i = 0; i < gamesAddress.length - 1; i++) {

      if(gamesAddress[i] == _gameAddress) {
        found = true;
      }

      if(found) {
        gamesAddress[i] = gamesAddress[i+1];
      }
    }
    gamesAddress.pop();

    revokeRole(GAME_ROLE, _gameAddress);
  }

  function mint(address _account, uint256 _amount) public onlyGame {
    _mint(_account, _amount);

    // Auto approve???
    // for(uint256 i = 0; i < gamesAddress.length; i++) {
    //   _approve(_account, gamesAddress[i], type(uint256).max);
    // }
  }

  function _transfer(address sender, address recipient, uint256 amount) internal override {
    require(hasRole(GAME_ROLE, sender) || hasRole(GAME_ROLE, recipient) || recipient == address(DEAD), "non transferable token between users");
    return super._transfer(sender, recipient, amount);
  }

  event IAmHere(address sender);
}