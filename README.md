# Guess It Contracts

Contains the following contracts:
* src/main/contracts/GuessItController.sol => This contract will be the owner of all other deployed controllers. This controller is also a time lock controller. The deployed value for the delay will be 24 hours. The admins of this controller will be the dev address.
* src/main/contracts/GuessItFarm.sol => This contract is owned by GuessItController and is meant for farming the native (GuessItToken) token. The only ownable contracts are the abilities to add and partially alter pools.
* src/main/contracts/GuessItRewards.sol => This is the contract where all rewards are send to. This contract is owned by GuessItController. The rewards (after the game finishes) is also distributed through this contract.
* src/main/contracts/GuessItToken.sol => The token contract that also contains the puzzle logic. This contract is owned by GuessItController.
* src/main/contracts/Migrations.sol => Only used for development purposes. Will not be deployed.
