const WBNB = artifacts.require("WBNB");

module.exports = function (deployer) {
  deployer.deploy(WBNB);
};
