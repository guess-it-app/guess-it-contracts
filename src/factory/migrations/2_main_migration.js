const Factory = artifacts.require("PancakeFactory");

module.exports = function (deployer, network) {
  if(network == 'development') {
    deployer.deploy(Factory, "0x79A723b2bC4AC05C7368fE8287cF5b87f154EA78");
  }
};
