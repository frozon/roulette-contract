// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract SPHEREg is ERC20, AccessControl {
  bytes32 public constant GAME_ROLE = keccak256("GAME");

  address public sphereToken;

  address constant DEAD = 0x000000000000000000000000000000000000dEaD;
  mapping(address => bool) private games;
  address[] private gamesAddress;

  struct PlayerInfo {
    uint256 cashedInAt;
    uint256 cashedInAmount;
  }

  mapping(address => PlayerInfo) public playerBank;

  constructor(address _sphereToken) ERC20("Sphere Game", "SPHEREg") {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

    sphereToken = _sphereToken;
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
  }

  function _transfer(address sender, address recipient, uint256 amount) internal override {
    require(hasRole(GAME_ROLE, sender) || hasRole(GAME_ROLE, recipient) || recipient == address(DEAD), "non transferable token between users");

    // Cash out: lock in period, 24h
    if(hasRole(GAME_ROLE, sender) && recipient != address(DEAD)) {
      PlayerInfo memory pInfo = playerBank[recipient];
      require(pInfo.cashedInAt <= block.timestamp + 1 days, "24h locked in period not ended");
    }

    // Cash in: limit amount to 1 rebase per 24h
    if(!hasRole(GAME_ROLE, sender)) {
      PlayerInfo memory pInfo = playerBank[sender];
      pInfo.cashedInAt = block.timestamp;

      uint256 senderBalance = IERC20(sphereToken).balanceOf(sender);

      // NOTE: super ugly should fetch reward yield from sphere contract
      uint256 rewardYield = 3943560072416;
      uint256 rewardYieldDenominator = 10000000000000000;
      uint256 reward = rewardYield / rewardYieldDenominator;

      uint256 maxCashInAmount = senderBalance * (1.0 + reward) ** 48.0 - senderBalance;

      uint256 cashedInAmount = pInfo.cashedInAt <= block.timestamp + 1 days ? 0 : pInfo.cashedInAmount;
      require(cashedInAmount + amount <= maxCashInAmount, "can not cash in more than 1 rebase per 24hours");

      pInfo.cashedInAt = block.timestamp;
      pInfo.cashedInAmount = cashedInAmount;
    }

    return super._transfer(sender, recipient, amount);
  }

  function setSphereToken(address _sphereToken) public onlyAdmin {
    require(_sphereToken != address(0x0), "Sphere Token can not be 0x0");
    sphereToken = _sphereToken;
  }
}