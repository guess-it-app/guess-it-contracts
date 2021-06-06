const Controller = artifacts.require("GuessItController");

module.exports = function (deployer, network) {
  if (network == 'development') {
    deployer.deploy(Controller, '0xAe3d3d617597Ef9899759b709c0bf46Ba03A31af', '0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0', 0, ['0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0']);
  }
};
