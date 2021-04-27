const Controller = artifacts.require("GuessItController");
const Token = artifacts.require("GuessItToken");
const Rewards = artifacts.require("GuessItRewards");
const Farm = artifacts.require("GuessItFarm");

contract("GuessItController", async () => {

  it("should create and own contracts", async () => {
    const controller = await Controller.deployed();
    
    const native = await controller.native.call();    
    assert.notEqual(native, null);
    const nativeContract = await Token.at(native);
    const nativeOwner = await nativeContract.owner.call();
    assert.equal(nativeOwner, controller.address);

    const rewards = await controller.rewards.call();    
    assert.notEqual(rewards, null);
    const rewardsContract = await Rewards.at(rewards);
    const rewardsOwner = await rewardsContract.owner.call();
    assert.equal(rewardsOwner, controller.address);

    const farm = await controller.farm.call();    
    assert.notEqual(farm, null);
    const farmContract = await Farm.at(farm);
    const farmOwner = await farmContract.owner.call();
    assert.equal(farmOwner, controller.address);
  });

  it("should create and assign roles", async () => {
    const controller = await Controller.deployed();
    
    const farm = await controller.farm.call();
    assert.notEqual(farm, null);

    const native = await controller.native.call();    
    assert.notEqual(native, null);
    const nativeContract = await Token.at(native);
    const minterRole = await nativeContract.getMinterRole.call();
    const hasMinterRole = await nativeContract.hasRole.call(minterRole, farm);    
    assert.ok(hasMinterRole);

    const rewards = await controller.rewards.call();    
    assert.notEqual(rewards, null);
    const rewardsContract = await Rewards.at(rewards);
    const transferRole = await rewardsContract.getTransferRole.call();
    const hasTransferRole = await rewardsContract.hasRole.call(transferRole, native);
    assert.ok(hasTransferRole);
  });
});