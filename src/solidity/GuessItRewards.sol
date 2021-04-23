// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./IPancakeRouter02.sol";

contract GuessItRewards is Ownable {

    uint public immutable devPercentage = 500; //50%, percentage of the rewards distributed to the dev address, in per mille
    
    address private _dev;
    uint private _perMille = 1000; // 100%

    constructor(address _devAddress) {
        _dev = _devAddress;
    }

    receive() external payable {
        uint devShare = msg.value * devPercentage / _perMille;
        payable(_dev).transfer(devShare);
    }

    function transferRewards(address payable _to, uint _amount) external onlyOwner {
        _to.transfer(_amount);
    }

    function setDev(address _newDevAddress) public onlyOwner {
        _dev = _newDevAddress;
    }

    function getDev() public view onlyOwner returns(address) {
        return _dev;
    }
}