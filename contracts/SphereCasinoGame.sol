// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SphereCasinoGame is Ownable {
  address public sphereToken;
  address public betToken;

  uint256 cashInFee = 0;
  uint256 cashOutFee = 0;
  uint256 feeDenominator = 100;

  address constant DEAD = 0x000000000000000000000000000000000000dEaD;

  constructor(address _sphereToken, address _betToken) {
    sphereToken = _sphereToken;
    betToken = _betToken;
  }

  function cashIn(uint256 amount) public {
    require(
      IERC20(sphereToken).transferFrom(msg.sender, address(this), amount),
      "cashIn failed"
    );

    if(cashInFee > 0) {
      uint256 feeAmount = amount * cashInFee / feeDenominator;
      amount -= feeAmount;
    }

    // FIXME: betToken should be mintable
    IERC20(betToken).mint(msg.sender, amount);

    emit CashIn(msg.sender, amount);
  }

  function cashOut(uint256 amount) public {
    require(amount <= IERC20(betToken).balanceOf(msg.sender), "amount too big");

    require(
      IERC20(betToken).transferFrom(msg.sender, address(DEAD), amount),
      "burn failed"
    );

    if(cashOutFee > 0) {
      uint256 feeAmount = amount * cashOutFee / feeDenominator;
      amount -= feeAmount;
    }

    require(
      IERC20(sphereToken).transferFrom(address(this), msg.sender, amount),
      "cashOut failed"
    );
  }

  /** Owner only functions */

  function addLiquidity(uint256 amount) public onlyOwner {
    require(
      IERC20(sphereToken).transferFrom(owner(), address(this), amount),
      "failed to add liquidity"
    );
    emit AddLiquidity(amount);
  }

  function removeLiquidity(uint256 amount) public onlyOwner {
    require(amount <= IERC20(sphereToken).balanceOf(address(this)), "not enough sphere to withdraw liquidity");

    require(
      IERC20(sphereToken).transfer(owner(), amount),
      "failed to transfer sphere"
    );
    emit RemoveLiquidity(amount);
  }

  function setSphereToken(address _sphereToken) public onlyOwner {
    require(_sphereToken != address(0x0), "sphere token address can not be 0x0");
    sphereToken = _sphereToken;
  }

  function setBetToken(address _betToken) public onlyOwner {
    require(_betToken != address(0x0), "bet token address can not be 0x0");
    betToken = _betToken;
  }

  function setFeeDenominator(uint256 _denominator) public onlyOwner {
    feeDenominator = _denominator;
  }

  function setCashInFee(uint256 _fee) public onlyOwner {
    require(_fee <= 25, "fee too high");
    cashInFee = _fee;
    emit SetCashInFee(cashInFee);
  }

  function setCashOutFee(uint256 _fee) public onlyOwner {
    require(_fee <= 25, "fee too high");
    cashOutFee = _fee;
    emit SetCashOutFee(cashOutFee);
  }

  function withdraw(address _token) public onlyOwner {
    require(
      IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this))),
      "withdraw failed"
    );
  }

  event AddLiquidity(uint256 amount);
  event RemoveLiquidity(uint256 amount);
  event CashIn(address user, uint256 amount);
  event CashOut(address user, uint256 amount);
  event SetCashOutFee(uint256 fee);
  event SetCashInFee(uint256 fee);
}