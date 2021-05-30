// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./IWETH.sol";

contract GuessItRewards is Ownable, AccessControl {
    event RewardsReceived(uint _amount);

    bytes32 public constant TRANSFER_ROLE = keccak256("TRASNFER_ROLE");
    address public immutable dev;
    address public immutable WBNB;
    uint public immutable devPercentage = 500; //50%, percentage of the rewards distributed to the dev address, in per mille
    
    uint private _perMille = 1000; // 100%

    constructor(address _dev, address _WBNB) {
        dev = _dev;
        WBNB = _WBNB;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    receive() external payable {
        uint devShare = msg.value * devPercentage / _perMille;
        payable(dev).transfer(devShare);
        emit RewardsReceived(msg.value - devShare);
    }

    function getTransferRole() public pure returns (bytes32) {
        return TRANSFER_ROLE;
    }

    function transferRewards(address payable _to, uint _amount) external {        
        require(hasRole(TRANSFER_ROLE, _msgSender()), "GuessItRewards: caller is not able to transfer");
        _to.transfer(_amount);
    }
}