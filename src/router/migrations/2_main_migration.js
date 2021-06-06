const Router = artifacts.require("PancakeRouter");

module.exports = function (deployer, network) {
  if(network == 'development') {
    deployer.deploy(Router, "0x330cba9fBcea917C0D16595f2579f5140b909AF9", "0x2622674B4Eb8d0628dEcDE230DE7B8911e0C8024");
  }
};
