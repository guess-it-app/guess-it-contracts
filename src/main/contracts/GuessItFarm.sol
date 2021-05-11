// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./GuessItToken.sol";
import "./GuessItRewards.sol";
import "./IPancakePair.sol";
import "./IWETH.sol";

contract GuessItFarm is Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);
    event SwappedForRewards(address _token, uint _amount);

    struct UserInfo {
        uint amount; // How many tokens the user has provided.
        uint lockupStarted; // Timestamp when the lock started.
        uint rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of RADSs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accumlatedNativePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accumlatedNativePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct PoolInfo {   
        address token; // Address of the token.
        uint amount; // The number of tokens in this pool
        bool isPair; // Indication whether this token is a IPancakePair        
        uint allocationPoints; // How many allocation points assigned to this pool. [native] to distribute per block.
        uint lastRewardBlock; // Last block number that [native] distribution occurs.
        uint accumlatedNativePerShare; // Accumulated [native] per share, times 1e12. See below.
        uint depositFee; // Deposit fee on this pool, in per mille (percentage) 
        uint lockup; // Lockup in the pool, in days
    }

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    uint public immutable nativePerBlock = 3000 ether; // min native tokens minted per block => 3000
    uint public totalAllocationPoints = 0; // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public immutable startBlock;
    GuessItToken public immutable native;
    GuessItRewards public immutable rewards;
    IPancakeRouter02 public immutable pancakeRouter;

    uint private _nativeShareMultiplier = 1e12;
    uint private _perMille = 1000; // 100%

    constructor(address _pancakeRouter, address _native, address payable _rewards, uint _startBlock) {
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        native = GuessItToken(_native);
        rewards = GuessItRewards(_rewards);        
        startBlock = _startBlock;
    }

    function getPoolInfo() external view returns (PoolInfo[] memory) {
        return poolInfo;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do. (Only if tokens are stored here.)
    function add(address _token, bool _isPair, uint _allocationPoints, uint _depositFee, uint _lockup, bool _withUpdate) external onlyOwner {
        require(!_getNativeFinished(), "GuessItFarm: game is already finished");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocationPoints += _allocationPoints;
        poolInfo.push(
            PoolInfo({
                token: _token,
                amount: 0,
                isPair: _isPair,
                allocationPoints: _allocationPoints,
                lastRewardBlock: lastRewardBlock,
                accumlatedNativePerShare: 0,
                depositFee: _depositFee,
                lockup: _lockup
            })
        );
    }

    // Update the given pool's [native] allocation point. Can only be called by the owner.
    function set(uint _pid, uint _allocationPoints, uint _depositFee, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocationPoints -= poolInfo[_pid].allocationPoints + _allocationPoints;
        poolInfo[_pid].allocationPoints = _allocationPoints;
        poolInfo[_pid].depositFee = _depositFee;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint _from, uint _to) public view returns (uint)
    {
        if (native.totalMinted() >= native.cap()) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending [native] on frontend.
    function getPendingNative(uint _pid, address _user) external view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accumlatedNativePerShare = pool.accumlatedNativePerShare;
        uint blockNumber = _getRewardBlock();
        if (blockNumber > pool.lastRewardBlock && pool.amount != 0) {
            uint multiplier = getMultiplier(pool.lastRewardBlock, blockNumber);
            uint nativeReward = multiplier * nativePerBlock * pool.allocationPoints / totalAllocationPoints;
            accumlatedNativePerShare += nativeReward * _nativeShareMultiplier / pool.amount;
        }
        return user.amount * accumlatedNativePerShare / _nativeShareMultiplier - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint blockNumber = _getRewardBlock();
        if (blockNumber <= pool.lastRewardBlock) {
            return;
        }
        if (pool.amount == 0) {
            pool.lastRewardBlock = blockNumber;
            return;
        }
        uint multiplier = getMultiplier(pool.lastRewardBlock, blockNumber);
        if (multiplier <= 0) {
            return;
        }
        uint mintableTokensLeft = native.cap() - native.totalMinted();
        if(mintableTokensLeft <= 0) {
            return;
        }

        uint tokensToMint = mintableTokensLeft >= nativePerBlock ? nativePerBlock : mintableTokensLeft;
        uint nativeReward = multiplier * tokensToMint * pool.allocationPoints / totalAllocationPoints;        
        if(nativeReward > 0) {
            native.mint(address(this), nativeReward);
        }
        pool.accumlatedNativePerShare += nativeReward * _nativeShareMultiplier / pool.amount;
        pool.lastRewardBlock = blockNumber;
    }

    // Deposit tokens for [native] allocation.  
    function deposit(uint _pid, uint _amount) external nonReentrant {      
        require(!_getNativeFinished(), "GuessItFarm: game is already finished");        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        updatePool(_pid);
       
        if(user.amount > 0) {           
            uint pending = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier - user.rewardDebt;
            if(pending > 0) {
                safeNativeTransfer(_msgSender(), pending);
            }
        }
        if (_amount > 0) {
            IERC20(pool.token).safeTransferFrom(_msgSender(), address(this), _amount);

            pool.amount += _amount;
            user.amount += _amount;
            if (pool.depositFee > 0) {
                uint depositFee = _amount / _perMille * pool.depositFee;
                bool success = _distributeDepositFee(pool, depositFee);
                // if we succesfully swapped the deposit fee, reduce the deposited amount
                if(success) {
                    user.amount -= depositFee;
                    pool.amount -= depositFee;
                }
            }

            // new deposits will reset the lockup
            user.lockupStarted = block.timestamp;
        }        
        user.rewardDebt = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier;
        emit Deposit(_msgSender(), _pid, _amount);
    }
    
    function max(uint a, uint b) private pure returns (uint) {
        return a > b ? a : b;
    }
    
    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }

    // Withdraw tokens
    function withdraw(uint _pid, uint _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(user.lockupStarted + pool.lockup * 1 days <= block.timestamp, "GuessItFarm: withdraw not allowed");
        require(user.amount > 0, "GuessItFarm: nothing to withdraw");
        require(user.amount >= _amount, "GuessItFarm: withdraw not allowed");
        updatePool(_pid);

        uint pending = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier - user.rewardDebt;
        if(pending > 0) {
            safeNativeTransfer(_msgSender(), pending);
        }
        if(_amount > 0) {
            user.amount -= _amount; 
            pool.amount -= _amount;         
            IERC20(pool.token).safeTransfer(_msgSender(), _amount);
        }
        user.rewardDebt = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier;
        emit Withdraw(_msgSender(), _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        uint amount = user.amount;
        pool.amount -= amount;
        user.amount = 0;
        user.rewardDebt = 0;
        IERC20(pool.token).safeTransfer(_msgSender(), amount);
        emit EmergencyWithdraw(_msgSender(), _pid, amount);
    }

    // Safe [native] transfer function, just in case if rounding error causes pool to not have enough
    function safeNativeTransfer(address _to, uint _nativeAmount) internal {
        uint nativeBalance = native.balanceOf(address(this));
        if (_nativeAmount > nativeBalance) {
            native.transfer(_to, nativeBalance);
        } else {
            native.transfer(_to, _nativeAmount);
        }
    }

    function _distributeDepositFee(PoolInfo storage pool, uint depositFee) private returns (bool) {
        if(pool.isPair) {
            return _removeLiquidityAndSwap(pool.token, address(rewards), depositFee);
        } 
        
        return _swap(pool.token, address(rewards), depositFee);
    }

    function _getNativeFinished() private view returns (bool) {
        return native.finished();
    }

    function _getRewardBlock() private view returns (uint) {        
        return _getNativeFinished() ? native.finishedBlock() : block.number;
    }

    function _removeLiquidityAndSwap(address _token, address _to, uint _amount) private returns (bool) {
        IPancakePair pair = IPancakePair(_token);
        address token0 = pair.token0();
        address token1 = pair.token1();
        bool success = true;
        pair.approve(address(pancakeRouter), 0);
        pair.approve(address(pancakeRouter), _amount);
        try pancakeRouter.removeLiquidity(token0, token1, _amount, 0, 0, address(this), block.timestamp) returns (uint amountA, uint amountB) {
            success = _swap(token0, _to, amountA) && _swap(token1, _to, amountB);    
            emit SwappedForRewards(_token, _amount);
        } catch {
            success = false;
        }
        pair.approve(address(pancakeRouter), 0);
        return success;
    }

    function _swap(address _token, address _to, uint _amount) private returns (bool) {
        bool success = true;

        if(_token == pancakeRouter.WETH()) {
            try IWETH(_token).transfer(_to, _amount) {
                emit SwappedForRewards(_token, _amount);  
            } catch {
                success = false;
            }
            return success;
        }

        // generate the pancake pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = pancakeRouter.WETH();

        // make the swap        
        IERC20(_token).safeIncreaseAllowance(address(pancakeRouter), _amount);
        try pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, 0, path, _to, block.timestamp) {
            emit SwappedForRewards(_token, _amount);         
        } catch {
            success = false;
        }
        return success;
    }
}