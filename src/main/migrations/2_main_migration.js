const Controller = artifacts.require("GuessItController");

module.exports = function (deployer, network) {
  if (network == 'development') {
    deployer.deploy(Controller, '0xFc20bAdc6FffFcFdf4E56C34c9FDf270bd769f73', '0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0', 0, ['0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0']);
  }
};
