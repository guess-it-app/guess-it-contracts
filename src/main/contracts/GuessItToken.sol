// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "./IPancakeRouter02.sol";
import "./IPancakeFactory.sol";
import "./GuessItRewards.sol";

contract GuessItToken is ERC20Snapshot, ERC20Burnable, ERC20Capped, AccessControl, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event GameStarted();
    event Guessed(address _from, string _solution, bool _guessed);
    event PriceUpdated(uint _guessPrice);
    event Withdrawn(address _to, uint amount);

    enum GameState { Created, LiquidityAdded, Started, Finished }
    enum UserState { Withdrawn }

    modifier inGameState(GameState state) {
        require(_state == state, "GuessItToken: invalid game state");
        _;
    }
    
    modifier notInGameState(GameState state) {
        require(_state != state, "GuessItToken: invalid game state");
        _;
    }

    modifier notInUserState(UserState state) {
        require(_userStates[_msgSender()] != state, "GuessItToken: invalid user state");
        _;
    }

    modifier lockSwap {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    struct Game {
        bytes32 puzzle; // the hashed puzzle (image)
        bytes32[] solutions; // the hashed solutions
        bool finished;
    }
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    GuessItRewards public immutable rewards;
    IPancakeRouter02 public immutable pancakeRouter;    
    uint public guesserPercentage = 150; //initial rewards percentage for the guesser of the puzzle, in per mille
    uint public transferPercentage = 980; //initial percentage of the amount that is allowed to be transfered, in per mille
    uint public rewardsPercentage = 500; //initial rewards percentage, in per mille

    bool _inSwap;
    uint private _totalMinted;
    mapping (address => bool) private _isExcludedFromFee;
    uint private _perMille = 1000; // 100%
    uint private _snapShotId;
    Game private _game;
    uint private _guessPrice;
    mapping (address => bool) private _guessers;
    GameState private _state;
    mapping (address => UserState) private _userStates;

    constructor(address _pancakeRouter, address payable _rewards) ERC20Capped(1e11 ether) ERC20("GuessIt Token", "GSSIT") {
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        rewards = GuessItRewards(_rewards);

        excludeFromFee(address(this));
        excludeFromFee(_rewards);        

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
    function getMinterRole() public pure returns (bytes32) {
        return MINTER_ROLE;
    }
    
    function addLiquidity(address _addr) external payable nonReentrant inGameState(GameState.Created) {
        require(msg.value == 20 ether, "GuessItToken: not enough liquidity provided");
        
        _mint(address(this), 1e7 ether); // preminted 0.01% of tokens to create liquidity pairs
        _approve(address(this), address(pancakeRouter), 1e7 ether);  
        pancakeRouter.addLiquidityETH{value:msg.value}(address(this), 1e7 ether, 1e7 ether, msg.value, _addr, block.timestamp);
        address pair = IPancakeFactory(pancakeRouter.factory()).getPair(address(this), pancakeRouter.WETH());
        _isExcludedFromFee[pair] = true;
        _approve(address(this), address(pancakeRouter), 0);

        _state = GameState.LiquidityAdded;
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function newGame(bytes32 puzzle_, bytes32[] calldata solutions_, uint guessPrice_) external inGameState(GameState.LiquidityAdded) {
        require(puzzle_ != "", "GuessItToken: puzzle should be provided");
        require(solutions_.length > 0, "GuessItToken: solutions should be provided");

        _game.puzzle = puzzle_;
        _game.solutions = solutions_;        

        emit GameStarted();
        _state = GameState.Started;

        _guessPrice = guessPrice_;
        emit PriceUpdated(guessPrice_);
    }

    function getGame() external view notInGameState(GameState.Created) returns (Game memory) {
        return _game;
    }

    function setPrice(uint guessPrice_) external onlyOwner inGameState(GameState.Started) {
        _guessPrice = guessPrice_;
        emit PriceUpdated(guessPrice_);
    }

    function getPrice() external view notInGameState(GameState.Created) returns (uint) {
        return _guessPrice;
    }

    function guess(string calldata solution, uint _amount) external inGameState(GameState.Started) returns (bool) {
        require(_amount == _guessPrice, "GuessItToken: guessing price conditions not met");
        
        uint amountForRewards = _amount * rewardsPercentage / _perMille;
        uint amountToBurn = _amount - amountForRewards;        
        if(amountToBurn > 0) {
           _burn(_msgSender(), amountToBurn);
        }
        if(amountForRewards > 0) {
           //approve(address(this), 0);
           //increaseAllowance(address(this), amountForRewards);
           //transfer(address(rewards), amountForRewards);
           //approve(address(this), 0);
           //rewards.tokenReceived(address(this), false, amountForRewards);
        }

        uint solutions = _game.solutions.length;
        bytes32 hashedSolution = sha256(abi.encodePacked(_toLower(solution)));
        for(uint i = 0; i < solutions; i++) {
            if(_game.solutions[i] == hashedSolution) {                
                _game.finished = _guessers[_msgSender()] = true;
                _snapShotId = _snapshot();
                _state = GameState.Finished;
                emit Guessed(_msgSender(), solution, true);                
                return true;
            } 
        }
        
        _game.finished = _guessers[_msgSender()] = false;
        emit Guessed(_msgSender(), solution, false);
        return false;
    }

    function claimableRewards() public view inGameState(GameState.Finished)  returns (uint) {
        if(!_game.finished) {
            return 0;
        }

        bool isGuesser = _guessers[_msgSender()];
        uint totalSupply = totalSupplyAt(_snapShotId);
        uint userSupply = balanceOfAt(_msgSender(), _snapShotId);

        uint guesserRewards = address(rewards).balance * guesserPercentage / _perMille;
        uint participationRewards = 0;
        if(totalSupply > 0) {
            participationRewards = (address(rewards).balance - guesserRewards) * userSupply / totalSupply;
        }

        return isGuesser ? guesserRewards + participationRewards : participationRewards;
    }

    function withdraw() external inGameState(GameState.Finished) notInUserState(UserState.Withdrawn) nonReentrant {
        uint amount = claimableRewards();
        require(amount > 0, "GuessItToken: there are no rewards to claim");
        require(amount > 0, "GuessItToken: there is nothing to withdraw"); 

        _userStates[_msgSender()] = UserState.Withdrawn;
        rewards.transferRewards(payable(_msgSender()), amount);        
        emit Withdrawn(_msgSender(), amount);        
    }

    function setTransferPercentage(uint _transferPercentage) external onlyOwner {
        require(_transferPercentage >= 950, "GuessItToken: invalid percentage");
        require(_transferPercentage <= 990, "GuessItToken: invalid percentage");
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

    function mint(address _to, uint _amount) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "GuessItToken: caller is not a minter");
        _mint(_to, _amount);
    }

    function totalMinted() public view returns (uint) {
        return _totalMinted;
    }

    // Returns for the sender the viewable puzzle share (in permille).
    function getViewablePuzzleShare() external view returns (uint) {
        if(_game.finished) {
            return _perMille;
        }

        uint userSupply = balanceOf(_msgSender());
        uint maxSupply = cap() - (totalMinted() - totalSupply());
        return userSupply * _perMille / maxSupply;
    }

    function _transfer(address _sender, address _recipient, uint _amount) internal override {
        if(_inSwap || _game.finished || isExcludedFromFee(_sender) || isExcludedFromFee(_recipient)) {
            super._transfer(_sender, _recipient, _amount);
            return;
        }

        uint amountToTransfer = _amount * transferPercentage / _perMille;
        uint amountLeft = _amount - amountToTransfer;
        uint amountForRewards = amountLeft * rewardsPercentage / _perMille;        
        uint amountToBurn = amountForRewards - amountForRewards;
        if(amountToBurn > 0) {
            _burn(_sender, amountToBurn);
        }
        if(amountForRewards > 0) {
           super._transfer(_msgSender(), address(this), amountForRewards);
           _swap(amountForRewards);
        }
        super._transfer(_sender, _recipient, amountToTransfer);
    }

    function _swap(uint _amount) private lockSwap {
        // generate the pancake pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();

        // make the swap
        _approve(address(this), address(pancakeRouter), 0);
        _approve(address(this), address(pancakeRouter), _amount);
        pancakeRouter.swapExactTokensForETH(_amount, 1, path, address(rewards), block.timestamp);
        _approve(address(this), address(pancakeRouter), 0);
    }

    function _mint(address account, uint amount) internal override(ERC20Capped, ERC20) {
        ERC20Capped._mint(account, amount);
        _totalMinted += amount;
    }

    function _beforeTokenTransfer(address from, address to, uint tokenId) internal override(ERC20Snapshot, ERC20) {
        super._beforeTokenTransfer(from, to, tokenId);
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