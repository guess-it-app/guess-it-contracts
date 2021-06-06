// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IPancakeRouter02.sol";
import "./GuessItToken.sol";

contract GuessItGame is ReentrancyGuard {

    event RewardsReceived(uint _amount);
    event GameStarted();
    event Guessed(address indexed _from, string indexed _solution, bool indexed _guessed);
    event Withdrawn(address indexed _to, uint _amount);
    event SwappedForRewards(address indexed _token, uint _amount);
   
    GuessItToken public immutable token;
    IPancakeRouter02 public immutable pancakeRouter;   
    uint public immutable rewardsPercentage = 500; // rewards percentage, in per mille    
    uint public immutable guessPrice;
    bytes32[] solutions;
    bool public finished = false;
    
    uint private _perMille = 1000; // 100%
    mapping (address => bool) private _guessers;

    constructor(address _pancakeRouter, address _token, bytes32[] memory _solutions, uint _guessPrice) payable {
        require(_solutions.length > 0, "GuessItGame: solutions should be provided");
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        token = GuessItToken(_token);
        
        solutions = _solutions;        
        guessPrice = _guessPrice;

        emit GameStarted();
    }

    receive() external payable {
        emit RewardsReceived(msg.value);
    }

    function guess(string calldata _solution, uint _amount) external returns (bool) {
        require(!finished, "GuessItGame: game is already finished");
        require(_amount == guessPrice, "GuessItGame: guessing price conditions not met");
        
        token.transferFrom(msg.sender, address(this), _amount);

        bytes32 hashedSolution = keccak256(abi.encodePacked(_toLower(_solution)));
        for(uint i = 0; i < solutions.length; i++) {
            if(solutions[i] == hashedSolution) {                
                finished = _guessers[msg.sender] = true;
                emit Guessed(msg.sender, _solution, true);                
                return true;
            } 
        }
        
        _guessers[msg.sender] = false;
        emit Guessed(msg.sender, _solution, false);
        return false;
    }

    function swap() public {
        uint amount = token.balanceOf(address(this));
        uint amountForRewards = amount * rewardsPercentage / _perMille;
        uint amountToBurn = amount - amountForRewards;

        if(amountToBurn > 0) {
           token.burn(amountToBurn);
        }
        if(amountForRewards > 0) {           
           _swap(amountForRewards);
        }
    }

    function withdraw() external nonReentrant {
        require(finished, "GuessItGame: game is not finished");
        require(_guessers[msg.sender], "GuessItGame: only guesser is allowed to withdraw");

        swap();
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
        emit Withdrawn(msg.sender, balance);
    }

    function _swap(uint _amount) private {
        // generate the pancake pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = pancakeRouter.WETH();

        // make the swap
        token.approve(address(pancakeRouter), _amount);
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, 1, path, address(this), block.timestamp);
        emit SwappedForRewards(address(this), _amount);
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