const Factory = artifacts.require("PancakeFactory");

module.exports = function (deployer, network) {
  if(network == 'development') {
    deployer.deploy(Factory, "0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0");
  }
};
