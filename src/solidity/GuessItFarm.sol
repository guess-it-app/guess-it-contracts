// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./GuessItToken.sol";
import "./IPancakeRouter02.sol";
import "./IPancakePair.sol";

contract GuessItFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);

    struct UserInfo {
        uint amount; // How many tokens the user has provided.
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
        bool isPair; // Indication whether this token is a IPancakePair
        uint allocationPoints; // How many allocation points assigned to this pool. [native] to distribute per block.
        uint lastRewardBlock; // Last block number that [native] distribution occurs.
        uint accumlatedNativePerShare; // Accumulated [native] per share, times 1e12. See below.
        uint depositFee; // Deposit fee on this pool, in per mille (percentage) 
    }

    IPancakeRouter02 public immutable pancakeRouter;
    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    uint public immutable nativePerBlock = 1e4 ether; // native tokens minted per block => 10,000
    uint public totalAllocationPoints = 0; // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public immutable startBlock;
    address public native;

    uint private _nativeShareMultiplier = 1e12;
    uint private _perMille = 1000; // 100%

    constructor(address _pancakeRouter, address _native) {
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        native = _native;
        startBlock = block.number;        
    }

    function getPoolInfo() external view returns (PoolInfo[] memory) {
        return poolInfo;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do. (Only if tokens are stored here.)
    function add(address _token, bool _isPair, uint _allocationPoints, uint _depositFee, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocationPoints += _allocationPoints;
        poolInfo.push(
            PoolInfo({
                token: _token,
                isPair: _isPair,
                allocationPoints: _allocationPoints,
                lastRewardBlock: lastRewardBlock,
                accumlatedNativePerShare: 0,
                depositFee: _depositFee
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
        if (GuessItToken(native).totalSupply() >= GuessItToken(native).cap()) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending [native] on frontend.
    function pendingNative(uint _pid, address _user) external view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accumlatedNativePerShare = pool.accumlatedNativePerShare;
        uint amount = IERC20(pool.token).balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && amount != 0) {
            uint multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint nativeReward = multiplier * nativePerBlock * pool.allocationPoints / totalAllocationPoints;
            accumlatedNativePerShare += nativeReward * _nativeShareMultiplier / amount;
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
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint amount = IERC20(pool.token).balanceOf(address(this));
        if (amount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        if (multiplier <= 0) {
            return;
        }
        uint mintableTokensLeft = GuessItToken(native).cap() - GuessItToken(native).totalSupply();
        uint tokensToMint = mintableTokensLeft >= nativePerBlock ? nativePerBlock : mintableTokensLeft;
        uint nativeReward = multiplier * tokensToMint * pool.allocationPoints / totalAllocationPoints;        
        GuessItToken(native).mint(address(this), nativeReward);

        pool.accumlatedNativePerShare += nativeReward * _nativeShareMultiplier / amount;
        pool.lastRewardBlock = block.number;
    }
   
    // Deposit tokens for [native] allocation.
    function deposit(uint _pid, uint _amount) external nonReentrant {       
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint pending = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier - user.rewardDebt;
            if (pending > 0) {
                safeNativeTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            IERC20(pool.token).safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFee > 0) {
                uint depositFee = _amount / _perMille * pool.depositFee;
                user.amount += _amount - depositFee;
                _distributeDepositFee(pool, depositFee); // distribute the deposit fee to the rewards pool
            } else {                   
                user.amount += _amount;
            }
        }
        user.rewardDebt = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw tokens
    function withdraw(uint _pid, uint _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount > 0, "Nothing to withdraw");
        require(user.amount >= _amount, "Withdraw not allowed");

        updatePool(_pid);
        uint pending = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier - user.rewardDebt;
        if(pending > 0) {
            safeNativeTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount -= _amount;            
            IERC20(pool.token).safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount * pool.accumlatedNativePerShare / _nativeShareMultiplier;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        IERC20(pool.token).safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe [native] transfer function, just in case if rounding error causes pool to not have enough
    function safeNativeTransfer(address _to, uint _nativeAmount) internal {
        uint nativeBalance = GuessItToken(native).balanceOf(address(this));
        if (_nativeAmount > nativeBalance) {
            GuessItToken(native).transfer(_to, nativeBalance);
        } else {
            GuessItToken(native).transfer(_to, _nativeAmount);
        }
    }

    function _distributeDepositFee(PoolInfo storage pool, uint depositFee) private {
        address rewardsAddr = GuessItToken(native).rewards.address;
        if(pool.isPair) {
            IPancakePair pair = IPancakePair(pool.token);
            address token0 = pair.token0();
            address token1 = pair.token1();
            (uint amountA, uint amountB) = pancakeRouter.removeLiquidity(token0, token1, depositFee, 0, 0, address(this), block.timestamp);
            _swapTokensForBnb(token0, rewardsAddr, amountA);
            _swapTokensForBnb(token1, rewardsAddr, amountB);
        } else {
            _swapTokensForBnb(rewardsAddr, pool.token, depositFee);
        }
    }
    
    function _swapTokensForBnb(address _token, address _to, uint _amount) private {
        // generate the pancake pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = pancakeRouter.WETH();

        // make the swap
        IERC(_token).approve(address(pancakeRouter), _amount);
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, 0, path, _to, block.timestamp);
    }
}