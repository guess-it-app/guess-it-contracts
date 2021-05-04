const Controller = artifacts.require("GuessItController");

module.exports = function (deployer, network) {
  if (network == 'development') {
    deployer.deploy(Controller, '0x2147A9D95D296d390B8427792E70174f1b9bf395', '0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0', 0, ['0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0'], { overwrite: false });
  }
};
