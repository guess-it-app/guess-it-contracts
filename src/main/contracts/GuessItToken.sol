// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "./IPancakeRouter02.sol";
import "./GuessItRewards.sol";

contract GuessItToken is ERC20Burnable, ERC20Capped, AccessControl, Ownable, ReentrancyGuard {

    event GameStarted();
    event Guessed(address indexed _from, string indexed _solution, bool indexed _guessed);
    event PriceUpdated(uint _from, uint _to);
    event Withdrawn(address indexed _to, uint _amount);
    event SwappedForRewards(address indexed _token, uint _amount);
    event TransferPerMilleChanged(uint _from, uint _to);
    event RewardsPerMilleChanged(uint _from, uint _to);
    event GuesserPerMilleChanged(uint _from, uint _to);

    enum GameState { Created, Started, Finished }

    modifier inGameState(GameState state) {
        require(_state == state, "GuessItToken: invalid game state");
        _;
    }
    
    modifier notInGameState(GameState state) {
        require(_state != state, "GuessItToken: invalid game state");
        _;
    }

    modifier lockSwap {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    struct Game {
        bytes32 puzzle; // the hashed puzzle
        bytes32[] solutions; // the hashed solutions
    }
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    GuessItRewards public immutable rewards;
    IPancakeRouter02 public immutable pancakeRouter;   
    bool public finished = false;
    uint public finishedBlock = 0; 
    uint public guesserPercentage = 50; //initial rewards percentage for the guesser of the puzzle, in per mille
    uint public transferPercentage = 970; //initial percentage of the amount that is allowed to be transfered, in per mille
    uint public rewardsPercentage = 500; //initial rewards percentage, in per mille

    bool _inSwap;
    uint private _totalMinted;
    mapping (address => bool) private _isExcludedFromFee;
    uint private _perMille = 1000; // 100%
    Game private _game;
    uint private _maxGuessPrice = 10000 ether;
    uint private _guessPrice;
    mapping (address => bool) private _guessers;
    bool private _guesserClaimed;
    GameState private _state;    

    constructor(address _pancakeRouter, address _dev, address payable _rewards) ERC20Capped(1e11 ether) ERC20("GuessIt Token", "GSSIT") {
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        rewards = GuessItRewards(_rewards);

        ERC20._mint(_dev, 1e9 ether); 
        excludeFromFee(address(this));
        excludeFromFee(_rewards);        

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
    function getMinterRole() public pure returns (bytes32) {
        return MINTER_ROLE;
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

    function newGame(bytes32 puzzle_, bytes32[] calldata solutions_, uint guessPrice_) external inGameState(GameState.Created) {        
        require(puzzle_ != "", "GuessItToken: puzzle should be provided");
        require(solutions_.length > 0, "GuessItToken: solutions should be provided");
        require(guessPrice_ <= _maxGuessPrice, "GuessItToken: invalid guess price provided");

        _game.puzzle = puzzle_;
        _game.solutions = solutions_;        

        emit GameStarted();
        _state = GameState.Started;

        _guessPrice = guessPrice_;
        emit PriceUpdated(0, guessPrice_);
    }

    function getGame() external view notInGameState(GameState.Created) returns (Game memory) {
        return _game;
    }

    function setPrice(uint guessPrice_) external onlyOwner inGameState(GameState.Started) {
        require(guessPrice_ <= _maxGuessPrice, "GuessItToken: invalid guess price provided");        
        emit PriceUpdated(_guessPrice, guessPrice_);
        _guessPrice = guessPrice_;
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
           super._transfer(_msgSender(), address(this), amountForRewards);
           _swap(amountForRewards);
        }

        uint solutions = _game.solutions.length;
        bytes32 hashedSolution = keccak256(abi.encodePacked(_toLower(solution)));
        for(uint i = 0; i < solutions; i++) {
            if(_game.solutions[i] == hashedSolution) {                
                finished = _guessers[_msgSender()] = true;
                finishedBlock = block.number;
                _state = GameState.Finished;
                emit Guessed(_msgSender(), solution, true);                
                return true;
            } 
        }
        
        _guessers[_msgSender()] = false;
        emit Guessed(_msgSender(), solution, false);
        return false;
    }

    function claimableRewards(uint _amount) public view inGameState(GameState.Finished) returns (uint) {
        require(_amount > 0, "GuessItToken: not a valid amount"); 

        uint totalSupply = totalSupply();     
        uint guesserRewards = !_guesserClaimed && _guessers[_msgSender()] ? address(rewards).balance * guesserPercentage / _perMille : 0;
        uint participationRewards = (address(rewards).balance - guesserRewards) * _amount / totalSupply;

        return guesserRewards + participationRewards;
    }

    function withdraw(uint _amount) external inGameState(GameState.Finished) nonReentrant {
        uint totalRewards = claimableRewards(_amount);
        
        rewards.transferRewards(payable(_msgSender()), totalRewards);              
        emit Withdrawn(_msgSender(), totalRewards);        
        _burn(_msgSender(), _amount);

        // guesser is only able to claim once
        if(!_guesserClaimed && _guessers[_msgSender()]) {
            _guesserClaimed = true;
        }
    }

    function setTransferPercentage(uint _transferPercentage) external onlyOwner {
        require(_transferPercentage >= 950, "GuessItToken: invalid percentage");
        require(_transferPercentage <= 990, "GuessItToken: invalid percentage");
        emit TransferPerMilleChanged(transferPercentage, _transferPercentage);
        transferPercentage = _transferPercentage;
    }

    function setRewardsPercentage(uint _rewardsPercentage) external onlyOwner {
        require(_rewardsPercentage >= 300, "GuessItToken: invalid percentage");
        require(_rewardsPercentage <= 1000, "GuessItToken: invalid percentage");
        emit RewardsPerMilleChanged(rewardsPercentage, _rewardsPercentage);
        rewardsPercentage = _rewardsPercentage;
    }

    function setGuesserPercentage(uint _guesserPercentage) external onlyOwner {
        require(_guesserPercentage >= 10, "GuessItToken: invalid percentage");
        require(_guesserPercentage <= 100, "GuessItToken: invalid percentage");
        GuesserPerMilleChanged(guesserPercentage, _guesserPercentage);
        guesserPercentage = _guesserPercentage;
    }

    function mint(address _to, uint _amount) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "GuessItToken: caller is not a minter");
        _mint(_to, _amount);
    }

    function totalMinted() public view returns (uint) {
        return _totalMinted;
    }

    function _transfer(address _sender, address _recipient, uint _amount) internal override {
        if(_inSwap || finished || isExcludedFromFee(_sender) || isExcludedFromFee(_recipient)) {
            super._transfer(_sender, _recipient, _amount);
            return;
        }

        uint amountToTransfer = _amount * transferPercentage / _perMille;
        uint amountLeft = _amount - amountToTransfer;
        uint amountForRewards = amountLeft * rewardsPercentage / _perMille;        
        uint amountToBurn = amountLeft - amountForRewards;
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
        _approve(address(this), address(pancakeRouter), _amount);
        try pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, 1, path, address(rewards), block.timestamp) {
            emit SwappedForRewards(address(this), _amount);
        } catch { // catch should only happen when there is not enough liquidity, then we burn the tokens
            _burn(address(this), _amount); 
        }
    }

    function _mint(address account, uint amount) internal override(ERC20Capped, ERC20) {
        ERC20Capped._mint(account, amount);
        _totalMinted += amount;
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