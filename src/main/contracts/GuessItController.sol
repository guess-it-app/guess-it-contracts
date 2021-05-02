// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../node_modules/@openzeppelin/contracts/governance/TimelockController.sol";
import "./GuessItRewards.sol";
import "./GuessItToken.sol";
import "./GuessItFarm.sol";

contract GuessItController is TimelockController {
    GuessItToken immutable public native;
    GuessItRewards immutable public rewards;
    GuessItFarm immutable public farm;

    constructor(address _pancakeRouter, address _dev, uint _minDelay, address[] memory _admins) TimelockController(_minDelay, _admins, _admins) {
        GuessItRewards rewardsContract = new GuessItRewards(_dev);
        GuessItToken nativeContract = new GuessItToken(_pancakeRouter, _dev, payable(address(rewardsContract)));
        GuessItFarm farmContract = new GuessItFarm(address(nativeContract), payable(address(rewardsContract)), block.number);

        nativeContract.grantRole(nativeContract.getMinterRole(), address(farmContract));
        nativeContract.transferOwnership(address(this));
        rewardsContract.grantRole(rewardsContract.getTransferRole(), address(nativeContract));
        rewardsContract.transferOwnership(address(this));        
        farmContract.transferOwnership(address(this));
        
        rewards = rewardsContract;
        native = nativeContract;
        farm = farmContract;
    }
}