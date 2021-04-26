// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IPancakeRouter02.sol";
import "./IPancakePair.sol";

contract GuessItRewards is Ownable, AccessControl {
    using SafeERC20 for IERC20;

    event TokenRewardsReceived(address _token, uint _amount);
    event BnbRewardsReceived(uint _amount);

    bytes32 public constant TRANSFER_ROLE = keccak256("TRASNFER_ROLE");
    address public dev;
    IPancakeRouter02 public immutable pancakeRouter;
    uint public immutable devPercentage = 500; //50%, percentage of the rewards distributed to the dev address, in per mille
    
    uint private _perMille = 1000; // 100%

    constructor(address _pancakeRouter, address _dev) {
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        dev = _dev;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    receive() external payable {
        uint devShare = msg.value * devPercentage / _perMille;
        payable(dev).transfer(devShare);
        emit BnbRewardsReceived(msg.value - devShare);
    }

    function getTransferRole() public pure returns (bytes32) {
        return TRANSFER_ROLE;
    }

    function tokenReceive(address _token, bool _isPair, address _from, uint _amount) external {
        IERC20(_token).safeApprove(address(this), 0);
        IERC20(_token).safeIncreaseAllowance(address(this), _amount);
        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        IERC20(_token).safeApprove(address(this), 0);
        emit TokenRewardsReceived(_token, _amount);

        if(_isPair) {
            _removeLiquidityAndSwap(_token, _amount);
        } else {
            _swap(_token, address(this), _amount);
        }
    }

    function transferRewards(address payable _to, uint _amount) external {        
        require(hasRole(TRANSFER_ROLE, _msgSender()), "GuessItRewards: caller is not able to transfer");
        _to.transfer(_amount);
    }

    function setDev(address _dev) external onlyOwner {
        dev = _dev;
    }

    function _removeLiquidityAndSwap(address _token, uint _amount) private {
        IPancakePair pair = IPancakePair(_token);
        address token0 = pair.token0();
        address token1 = pair.token1();
        pair.approve(address(pancakeRouter), _amount);
        (uint amountA, uint amountB) = pancakeRouter.removeLiquidity(token0, token1, _amount, 0, 0, address(this), block.timestamp);
        _swap(token0, address(this), amountA);
        _swap(token1, address(this), amountB);
    }

    function _swap(address _token, address _to, uint _amount) private {
        // generate the pancake pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = pancakeRouter.WETH();

        // make the swap
        IERC20(_token).safeApprove(address(pancakeRouter), 0);
        IERC20(_token).safeIncreaseAllowance(address(pancakeRouter), _amount);
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, 0, path, _to, block.timestamp);
        IERC20(_token).safeApprove(address(pancakeRouter), 0);
    }
}