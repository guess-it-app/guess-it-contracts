// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./IPancakeRouter02.sol";
import "./IPancakeFactory.sol";
import "./GuessItRewards.sol";

contract GuessItToken is ERC20Snapshot, ERC20Burnable, ERC20Capped, Ownable, ReentrancyGuard {
    
    event GameStarted();
    event Guessed(address _from, string _solution, bool _guessed);
    event PriceUpdated(uint _guessPrice);
    event Withdrawn(address _to, uint amount);

    enum GameState { Created, LiquidityAdded, Started, Finished }
    enum UserState { Claimed, Withdrawn }

    modifier inGameState(GameState state) {
        require(_state == state, "GuessItToken: invalid game state");
        _;
    }
    
    modifier notInGameState(GameState state) {
        require(_state != state, "GuessItToken: invalid game state");
        _;
    }

    modifier inUserState(UserState state) {
        require(_userStates[msg.sender] == state, "GuessItToken: invalid user state");
        _;
    }

    modifier notInUserState(UserState state) {
        require(_userStates[msg.sender] != state, "GuessItToken: invalid user state");
        _;
    }

    struct Game {
        bytes32 puzzle; // the hashed puzzle (image)
        bytes32[] solutions; // the hashed solutions
        bool started;
        bool finished;
    }
    
    GuessItRewards public immutable rewards;
    IPancakeRouter02 public immutable pancakeRouter;
    uint public guessPrice;
    uint public guesserPercentage = 150; //initial rewards percentage for the guesser of the puzzle, in per mille
    uint public transferPercentage = 980; //initial burn percentage of the transfer, in per mille
    uint public rewardsPercentage = 500; //initial rewards percentage, in per mille

    uint private _perMille = 1000; // 100%
    uint private _snapShotId;
    Game private _game;
    mapping (address => uint) private _pendingWithdrawals;
    mapping (address => bool) private _guessers;
    GameState private _state;
    mapping (address => UserState) private _userStates;

    constructor(address _pancakeRouter, address _dev) ERC20Capped(1e11 ether) ERC20("GuessIt Token", "GSSIT") {
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        rewards = new GuessItRewards(_dev);
    }
    
    function addLiquidity() external payable onlyOwner() inGameState(GameState.Created) {
        require(msg.value == 20 ether, "GuessItToken: not enough liquidity provided");
        ERC20._mint(address(this), 1e7 ether); // preminted 0.01% of tokens to create liquidity pairs
        _approve(address(this), address(pancakeRouter), 1e7 ether); // approve the router to spend tokens to create liquidity pairs        
        pancakeRouter.addLiquidityETH{value:msg.value}(address(this), 1e7 ether, 1e7 ether, msg.value, getDev(), block.timestamp + 1 minutes);
    }

    function newGame(Game calldata game) external onlyOwner() inGameState(GameState.LiquidityAdded) {
        require(game.puzzle != "", "GuessItToken: puzzle should be provided");
        require(game.solutions.length > 0, "GuessItToken: solutions should be provided");

        _game.puzzle = game.puzzle;
        _game.solutions = game.solutions;
        _game.started = true;
        _game.finished = false;

        emit GameStarted();
        _state = GameState.Started;
    }

    function getGame() external view notInGameState(GameState.Created) returns (Game memory) {
        return _game;
    }

    function setPrices(uint _guessPrice) external onlyOwner() inGameState(GameState.Started) {
        guessPrice = _guessPrice;
        emit PriceUpdated(_guessPrice);
    }

    function guess(string calldata solution, uint _amount) external inGameState(GameState.Started) returns (bool) {
        require(_amount == guessPrice, "GuessItToken: guessing price conditions not met");
        uint amountForRewards = _amount * rewardsPercentage / _perMille;
        uint amountToBurn = _amount - amountForRewards;        
        _burn(msg.sender, amountToBurn);
        _swapTokensForBnb(msg.sender, address(rewards), amountForRewards);

        uint solutions = _game.solutions.length;
        bytes32 hashedSolution = sha256(abi.encodePacked(_toLower(solution)));
        for(uint i = 0; i < solutions; i++) {
            if(_game.solutions[i] == hashedSolution) {                
                _game.finished = _guessers[msg.sender] = true;
                _snapShotId = _snapshot();
                _state = GameState.Finished;
                emit Guessed(msg.sender, solution, true);                
                return true;
            }
        }
        
        _game.finished = _guessers[msg.sender] = false;
        emit Guessed(msg.sender, solution, false);
        return false;
    }

    function claimableRewards() public view inGameState(GameState.Finished) notInUserState(UserState.Withdrawn) returns (uint) {
        require(_game.started, "GuessItToken: there is no active game");
        if(!_game.finished) {
            return 0;
        }

        bool isGuesser = _guessers[msg.sender];
        uint totalSupply = totalSupplyAt(_snapShotId);
        uint userSupply = balanceOfAt(msg.sender, _snapShotId);

        uint guesserRewards = address(rewards).balance * guesserPercentage / _perMille;
        uint participationRewards = 0;
        if(totalSupply > 0) {
            participationRewards = (address(rewards).balance - guesserRewards) * userSupply / totalSupply;
        }

        return isGuesser ? guesserRewards + participationRewards : participationRewards;
    }

    function claimRewards() external inGameState(GameState.Finished) notInUserState(UserState.Withdrawn) {
        uint rewardsToClaim = claimableRewards();
        require(rewardsToClaim > 0, "GuessItToken: there are no rewards to claim");
    
        _pendingWithdrawals[msg.sender] = rewardsToClaim;
        _userStates[msg.sender] = UserState.Claimed;
    }

    function withdraw() external inGameState(GameState.Finished) inUserState(UserState.Claimed) nonReentrant {
        uint amount = _pendingWithdrawals[msg.sender];
        require(amount > 0, "GuessItToken: there is nothing to withdraw");        
        _pendingWithdrawals[msg.sender] = 0;
        _userStates[msg.sender] = UserState.Withdrawn;
        GuessItRewards(rewards).transferRewards(payable(msg.sender), amount);
        emit Withdrawn(msg.sender, amount);        
    }

    function setTransferPercentage(uint _transferPercentage) external onlyOwner {
        require(_transferPercentage >= 950, "GuessItToken: invalid percentage");
        require(_transferPercentage <= 1000, "GuessItToken: invalid percentage");
        transferPercentage = _transferPercentage;
    }

    function setRewardsPercentage(uint _rewardsPercentage) external onlyOwner {
        require(_rewardsPercentage >= 300, "GuessItToken: invalid percentage");
        require(_rewardsPercentage <= 1000, "GuessItToken: invalid percentage");
        rewardsPercentage = _rewardsPercentage;
    }

    function setGuesserPercentage(uint _guesserPercentage) external onlyOwner {
        require(_guesserPercentage >= 100, "GuessItToken: invalid percentage");
        require(_guesserPercentage <= 200, "GuessItToken: invalid percentage");
        guesserPercentage = _guesserPercentage;
    }

    function setDev(address _dev) public onlyOwner {
        rewards.setDev(_dev);
    }

    function getDev() public view returns(address) {
        return rewards.getDev();
    }

    function mint(address _to, uint _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function _transfer(address _sender, address _recipient, uint _amount) internal override {
        uint amountToTransfer = _amount * transferPercentage / _perMille;
        uint amountLeft = _amount - amountToTransfer;
        uint amountForRewards = amountLeft * rewardsPercentage / _perMille;
        uint amountToBurn = amountForRewards - amountForRewards;
        _burn(_sender, amountToBurn);
        _swapTokensForBnb(_sender, address(rewards), amountForRewards);
        super._transfer(_sender, _recipient, amountToTransfer);
    }

    function _mint(address account, uint amount) internal override(ERC20Capped, ERC20) {
        ERC20Capped._mint(account, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint tokenId) internal override(ERC20Snapshot, ERC20) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _swapTokensForBnb(address _from, address _to, uint _amount) private {
        // generate the pancake pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = pancakeRouter.WETH();

        // make the swap
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, 0, path, _to, block.timestamp);
    }

    function _toLower(string calldata str) private pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
            // Uppercase character...
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                // So we add 32 to make it lowercase
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
}