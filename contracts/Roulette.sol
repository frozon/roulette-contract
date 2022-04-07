// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/dev/VRFConsumerBase.sol";

import "./SphereCasinoGame.sol";

interface DAIPermit {
    function permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s) external;
}

enum BetType {
    Number,
    Color,
    Even,
    Column,
    Dozen,
    Half
}

enum Color {
    Green,
    Red,
    Black
}
/**
 * @title Sakura casino roulette
 */
contract Roulette is SphereCasinoGame, VRFConsumerBase, ERC20 {
    struct Bet {
        BetType betType;
        uint8 value;
        uint256 amount;
    }
    
    mapping (bytes32 => Bet[]) _rollRequestsBets;
    mapping (bytes32 => bool) _rollRequestsCompleted;
    mapping (bytes32 => address) _rollRequestsSender;
    mapping (bytes32 => uint8) _rollRequestsResults;
    mapping (bytes32 => uint256) _rollRequestsTime;
    mapping (bytes32 => uint256) _rollRequestsMaxWin;

    uint256 BASE_SHARES = uint256(10) ** 18;
    uint256 public current_liquidity = 0;
    uint256 public locked_liquidity = 0;
    uint256 public collected_fees = 0;
    address public bet_token;
    uint256 public max_bet;
    uint256 public bet_fee;
    uint256 public redeem_min_time = 2 hours;
    uint256 public burn_fee = 50;

    // Minimum required liquidity for betting 1 token
    // uint256 public minLiquidityMultiplier = 36 * 10;
    uint256 public minLiquidityMultiplier = 100;
    
    // Constant value to represent an invalid result
    uint8 public constant INVALID_RESULT = 99;

    mapping (uint8 => Color) COLORS;
    uint8[18] private RED_NUMBERS = [
        1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36
    ];

    event BetRequest(bytes32 requestId, address sender);
    event BetResult(bytes32 requestId, uint256 randomResult, uint256 payout);

    // Chainlink VRF Data
    bytes32 internal keyHash;
    uint256 internal fee;
    event RequestedRandomness(bytes32 requestId);

    /**
     * Contract's constructor
     * @param _bet_token address of the token used for bets and liquidity
     * @param _vrfCoordinator address of Chainlink's VRFCoordinator contract
     * @param _link address of the LINK token
     * @param _keyHash public key of Chainlink's VRF
     * @param _fee fee to be paid in LINK to Chainlink's VRF
     */
    constructor(
        address _sphere_token,
        address _bet_token,
        address _vrfCoordinator,
        address _link,
        bytes32 _keyHash,
        uint _fee
    )  SphereCasinoGame(_sphere_token, _bet_token) ERC20("SAKURA_V1", "SV1") VRFConsumerBase(_vrfCoordinator, _link) public {
        keyHash = _keyHash;
        fee = _fee; 
        bet_token = _bet_token;
        max_bet = 10**20;
        bet_fee = 0;

        // Set up colors
        COLORS[0] = Color.Green;
        for (uint8 i = 1; i < 37; i++) {
            COLORS[i] = Color.Black;
        }
        for (uint8 i = 0; i < RED_NUMBERS.length; i++) {
            COLORS[RED_NUMBERS[i]] = Color.Red;
        }
    }

    /**
     * Roll bets
     * @param bets list of bets to be played
     * @param randomSeed random number seed for the VRF
     */
    function rollBets(Bet[] memory bets, uint256 randomSeed) public {
        uint256 amount = 0;

        for (uint index = 0; index < bets.length; index++) {
            require(bets[index].value < 37);
            amount += bets[index].amount;
        }

        require(amount <= getMaxBet(), "Your bet exceeds the max allowed");
        require(IERC20(bet_token).balanceOf(address(this)) - locked_liquidity >= getMaxWinFromBets(bets), "can not cover win");

        // Collect token
        IERC20(bet_token).transferFrom(msg.sender, address(this), amount + bet_fee);

        uint256 maxWin = getMaxWinFromBets(bets);
        locked_liquidity += maxWin;

        bytes32 requestId = getRandomNumber(randomSeed);
        emit BetRequest(requestId, msg.sender);

        _rollRequestsSender[requestId] = msg.sender;
        _rollRequestsCompleted[requestId] = false;
        _rollRequestsTime[requestId] = block.timestamp;
        _rollRequestsMaxWin[requestId] = maxWin;
        for (uint i; i < bets.length; i++) {
            _rollRequestsBets[requestId].push(bets[i]);
        }
    }

    /**
     * Roll bets: ONLY FOR ERC20 TOKENS WITHOUT PERMIT FUNCTION
     * @param bets list of bets to be played
     * @param randomSeed random number seed for the VRF
     */
    // function rollBets(Bet[] memory bets, uint256 randomSeed) public {
    //     rollBets(bets, randomSeed, 0, 0, false, 0, 0, 0);
    // }

    /**
     * Creates a randomness request for Chainlink VRF
     * @param userProvidedSeed random number seed for the VRF
     * @return requestId id of the created randomness request
     */
    function getRandomNumber(uint256 userProvidedSeed) private returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        bytes32 _requestId = requestRandomness(keyHash, fee, userProvidedSeed);
        emit RequestedRandomness(_requestId);
        return _requestId;
    }

    /**
     * Randomness fulfillment to be called by the VRF Coordinator once a request is resolved
     * This function makes the expected payout to the user
     * @param requestId id of the resolved request
     * @param randomness generated random number
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        require(_rollRequestsCompleted[requestId] == false);
        uint8 result = uint8(randomness % 37);
        Bet[] memory bets = _rollRequestsBets[requestId];
        // uint256 rollLockedAmount = getRollRequestAmount(requestId) * 36;

        // release locked liquidity
        locked_liquidity -= _rollRequestsMaxWin[requestId];

        uint256 totalBetAmount = 0;

        uint256 amount = 0;
        for (uint index = 0; index < bets.length; index++) {
            BetType betType = BetType(bets[index].betType);

            uint8 betValue = uint8(bets[index].value);

            uint256 betAmount = bets[index].amount;
            totalBetAmount += betAmount;

            if (betType == BetType.Number && result == betValue) {
                amount += betAmount * 36;
                continue;
            }
            if (result == 0) {
                continue;
            }
            if (betType == BetType.Color && uint8(COLORS[result]) == betValue) {
                amount += betAmount * 2;
                continue;
            }
            if (betType == BetType.Even && result % 2 == betValue) {
                amount += betAmount * 2;
                continue;
            }
            if (betType == BetType.Column && result % 3 == betValue) {
                amount += betAmount * 3;
                continue;
            }
            if (betType == BetType.Dozen && betValue * 12 < result && result <= (betValue + 1) * 12) {
                amount += betAmount * 3;
                continue;
            }
            if (betType == BetType.Half && (betValue != 0 ? (result > 19) : (result <= 19))) {
                amount += betAmount * 2;
                continue;
            }
        }

        _rollRequestsResults[requestId] = result;
        _rollRequestsCompleted[requestId] = true;

        if(burn_fee > 0 && amount < totalBetAmount) {
            uint256 burnAmount = (totalBetAmount - amount) * burn_fee / 100;
            if(amount > 0) {
                amount -= burnAmount;
            }
            IERC20(bet_token).transfer(address(DEAD), burnAmount);
        }

        if (amount > 0) {
            IERC20(bet_token).transfer(_rollRequestsSender[requestId], amount);
        }

        emit BetResult(requestId, result, amount);
    }

    function getMaxWinFromBets(Bet[] memory bets) private returns (uint256) {
        uint256 lockedValue = 0;

        for (uint index = 0; index < bets.length; index++) {
            BetType betType = BetType(bets[index].betType);

            uint8 betValue = uint8(bets[index].value);

            uint256 betAmount = bets[index].amount;

            if (betType == BetType.Number) {
                lockedValue += betAmount * 36;
                continue;
            }
            if (betType == BetType.Color) {
                lockedValue += betAmount * 2;
                continue;
            }
            if (betType == BetType.Even) {
                lockedValue += betAmount * 2;
                continue;
            }
            if (betType == BetType.Column) {
                lockedValue += betAmount * 3;
                continue;
            }
            if (betType == BetType.Dozen) {
                lockedValue += betAmount * 3;
                continue;
            }
            if (betType == BetType.Half) {
                lockedValue += betAmount * 2;
                continue;
            }
        }

        return lockedValue;
    }

    /**
     * Pays back the roll amount to the user if more than two hours passed and the random request has not been resolved yet
     * @param requestId id of random request
     */
    function redeem(bytes32 requestId) external {
        require(_rollRequestsCompleted[requestId] == false, 'requestId already completed');
        require(block.timestamp - _rollRequestsTime[requestId] > redeem_min_time, 'Redeem time not passed');

        Bet[] memory bets = _rollRequestsBets[requestId];

        _rollRequestsCompleted[requestId] = true;
        _rollRequestsResults[requestId] = INVALID_RESULT;

        uint256 amount = getRollRequestAmount(requestId);

        locked_liquidity -= getMaxWinFromBets(bets);

        IERC20(bet_token).transfer(_rollRequestsSender[requestId], amount);

        emit BetResult(requestId, _rollRequestsResults[requestId], amount);
    }

    /**
     * Returns the roll amount of a request
     * @param requestId id of random request
     * @return amount of the roll of the request
     */
    function getRollRequestAmount(bytes32 requestId) internal view returns(uint256) {
        Bet[] memory bets = _rollRequestsBets[requestId];
        uint256 amount = 0;

        for (uint index = 0; index < bets.length; index++) {
            uint256 betAmount = bets[index].amount;
            amount += betAmount;
        }

        return amount;
    }

    /**
     * Returns a request state
     * @param requestId id of random request
     * @return indicates if request is completed
     */
    function isRequestCompleted(bytes32 requestId) public view returns(bool) {
        return _rollRequestsCompleted[requestId];
    }

    /**
     * Returns the address of a request
     * @param requestId id of random request
     * @return address of the request sender
     */
    function requesterOf(bytes32 requestId) public view returns(address) {
        return _rollRequestsSender[requestId];
    }

    /**
     * Returns the result of a request
     * @param requestId id of random request
     * @return numeric result of the request in range [0, 38], 99 means invalid result from a redeem
     */
    function resultOf(bytes32 requestId) public view returns(uint8) {
        return _rollRequestsResults[requestId];
    }

    /**
     * Returns all the bet details in a request
     * @param requestId id of random request
     * @return a list of (betType, value, amount) tuplets from the request
     */
    function betsOf(bytes32 requestId) public view returns(Bet[] memory) {
        return _rollRequestsBets[requestId];
    }

    /**
     * Returns the current bet fee
     * @return the bet fee
     */
    function getBetFee() public view returns(uint256) {
        return bet_fee;
    }

    /**
     * Returns the current maximum fee
     * @return the maximum bet
     */
    function getMaxBet() public view returns(uint256) {
        uint256 maxBetForLiquidity = getCurrentLiquidity() / minLiquidityMultiplier;
        if (max_bet > maxBetForLiquidity) {
            return maxBetForLiquidity;
        }
        return max_bet;
    }

    /**
     * Returns the collected fees so far
     * @return the collected fees
     */
    function getCollectedFees() public view returns(uint256) {
        return collected_fees;
    }
    
    /**
     * Sets the bet fee
     * @param _bet_fee the new bet fee
     */
    function setBetFee(uint256 _bet_fee) external onlyOwner {
        bet_fee = _bet_fee;
    }

    /**
     * Sets the maximum bet
     * @param _max_bet the new maximum bet
     */
    function setMaxBet(uint256 _max_bet) external onlyOwner {
        max_bet = _max_bet;
    }

    /**
     * Sets minimum liquidity needed for betting 1 token
     * @param _minLiquidityMultiplier the new minimum liquidity multiplier
     */
    function setMinLiquidityMultiplier(uint256 _minLiquidityMultiplier) external onlyOwner {
        minLiquidityMultiplier = _minLiquidityMultiplier;
    }

    /**
     * Withdraws the collected fees
     */
    function withdrawFees() external onlyOwner {
        uint256 _collected_fees = collected_fees;
        collected_fees = 0;
        IERC20(bet_token).transfer(owner(), _collected_fees);
    }

    /**
     * Sets the value of Chainlink's VRF fee
     */
    function setVRFFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    /**
     * Sets the burn fee when player lose
     */
    function setBurnFee(uint256 _fee) public onlyOwner {
        burn_fee = _fee;
    }
}
