// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WATER is ERC20 {
    constructor(uint256 initialSupply) ERC20("WaterToken", "WATER") {
        _mint(msg.sender, initialSupply);
    }
}

contract MELON is ERC20 {
    constructor(uint256 initialSupply) ERC20("MelonToken", "MELON") {
        _mint(msg.sender, initialSupply);
    }
}

contract FruitStand {

    struct UserStake {
        uint startBlock;
        uint stakeAmount;
    }

    ERC20 immutable water;
    ERC20 immutable melon;
    mapping(address => UserStake) userStakes;
    uint[301] private blocksToMultiplier;

    constructor(address _water, address _melon) {
        water = ERC20(_water);
        melon = ERC20(_melon);
        initializeMultipliers();
    }

    function stake(uint _amount) external {
        require(_amount > 0, "FruitStand: Stake amount must be greater than zero");
        if (userStakes[msg.sender].startBlock != 0) {
            // Pay out current stake
            payout(msg.sender, userStakes[msg.sender]);
        }
        water.transferFrom(msg.sender, address(this), _amount);
        UserStake memory newStake = UserStake({startBlock : block.number, stakeAmount : _amount});
        userStakes[msg.sender] = newStake;
    }

    function unstake() external {
        UserStake memory userStake = userStakes[msg.sender];
        require(userStake.startBlock != 0, "FruitStand: User have not staked");
        payout(msg.sender, userStake);
        water.transfer(msg.sender, userStake.stakeAmount);
        delete userStakes[msg.sender];
    }

    function payout(address user, UserStake memory stake) internal returns (uint8 errCode) {
        uint blockDelta = block.number - stake.startBlock;
        if (blockDelta > 300) {
            blockDelta = 300;
        }
        uint rewardAmount = blocksToMultiplier[blockDelta] * stake.stakeAmount;
        melon.transfer(user, rewardAmount);
        return 0;
    }

    function initializeMultipliers() private {
        blocksToMultiplier[0] = 0;
        blocksToMultiplier[1] = 1;
        uint pre = 0;
        uint cur = 1;
        for (uint i = 2; i <= 300; i++) {
            (cur, pre) = (cur + pre, cur);
            blocksToMultiplier[i] = cur;
        }
    }
}