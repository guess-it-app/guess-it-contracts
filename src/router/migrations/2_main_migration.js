const Router = artifacts.require("PancakeRouter");

module.exports = function (deployer, network) {
  if(network == 'development') {
    deployer.deploy(Router, "0x8a41C3A77bC5Df996490542E30f588305018c9F9", "0x79A723b2bC4AC05C7368fE8287cF5b87f154EA78");
  }
};
