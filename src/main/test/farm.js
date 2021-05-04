const Controller = artifacts.require("GuessItController");
const Token = artifacts.require("GuessItToken");
const Farm = artifacts.require("GuessItFarm");
const Rewards = artifacts.require("GuessItRewards");
const Router = artifacts.require("IPancakeRouter02");
const Factory = artifacts.require("IPancakeFactory");
const Pair = artifacts.require("IPancakePair");

contract("GuessItController", async accounts => {
    const truffleAssert = require('truffle-assertions');
    const BN = web3.utils.BN;

    async function getController() {
        return await Controller.deployed();
    }

    async function startNewGame(nativeContract, puzzle = "puzzle", solutions = ["solution 1", "solution 2"], guessPrice = "10") {
        await nativeContract.newGame(web3.utils.keccak256(puzzle), solutions.map(web3.utils.keccak256), web3.utils.toWei(guessPrice));
    }

    async function addLiquidity(controller, farmContract) {
        const router = await farmContract.pancakeRouter.call();
        assert.notEqual(router, null);
        const routerContract = await Router.at(router);

        const factory = await routerContract.factory.call();
        assert.notEqual(factory, null);
        const factoryContract = await Factory.at(factory);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        const wbnb = await routerContract.WETH.call();
        await factoryContract.createPair(native, wbnb);
        const pair = await factoryContract.getPair.call(native, wbnb);

        let excluded = nativeContract.contract.methods.excludeFromFee(pair).encodeABI();
        await controller.schedule(native, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.execute(native, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        await nativeContract.approve(router, web3.utils.toWei("10000"));
        await routerContract.addLiquidityETH(native, web3.utils.toWei("10000"), web3.utils.toWei("10000"), web3.utils.toWei("1"), accounts[0], Date.now(), { value: web3.utils.toWei("1") });

        return pair;
    }

    it("is correctly deployed", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const router = await farmContract.pancakeRouter.call();
        assert.notEqual(router, null);

        const rewards = await farmContract.rewards.call();
        assert.notEqual(rewards, null);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
    });

    it("is deployed and pools are added and updated", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 0, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        let pools = await farmContract.getPoolInfo.call();
        assert.equal(adds.length, pools.length);

        const set = farmContract.contract.methods.set(0, 500, 0, false).encodeABI();
        await controller.schedule(farm, 0, set, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.execute(farm, 0, set, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        pools = await farmContract.getPoolInfo.call();
        assert.equal(500, pools[0].allocationPoints);
    });

    it("is deployed, pools are added and native is deposited", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 0, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        let pools = await farmContract.getPoolInfo.call();
        assert.equal(adds.length, pools.length);

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        const tx = await farmContract.deposit(0, web3.utils.toWei("1000"));

        truffleAssert.eventEmitted(tx, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });
    });

    it("is deployed, pools are added with deposit fee and native is deposited and withdrawn", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 10, 0, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        let pools = await farmContract.getPoolInfo.call();
        assert.equal(adds.length, pools.length);

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        const txDeposit = await farmContract.deposit(0, web3.utils.toWei("1000"));

        truffleAssert.eventEmitted(txDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });

        truffleAssert.eventEmitted(txDeposit, 'SwappedForRewards', (ev) => {
            return ev._token == native && ev._amount > 0;
        });

        const rewards = await farmContract.rewards.call();
        const balance = await web3.eth.getBalance(rewards);
        assert.notEqual(balance, 0);

        var txWithdraw = await farmContract.withdraw(0, web3.utils.toWei("900"));

        truffleAssert.eventEmitted(txWithdraw, 'Withdraw', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("900");
        });
    });

    it("is deployed, pools are added with deposit fee and pair is deposited", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 0, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 10, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        let pools = await farmContract.getPoolInfo.call();
        assert.equal(adds.length, pools.length);

        const pairContract = await Pair.at(pair);

        await pairContract.approve(farm, web3.utils.toWei("10"));
        const tx = await farmContract.deposit(1, web3.utils.toWei("10"));

        truffleAssert.eventEmitted(tx, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 1 && ev.amount == web3.utils.toWei("10");
        });

        truffleAssert.eventEmitted(tx, 'SwappedForRewards', (ev) => {
            return ev._token == pair && ev._amount > 0;
        });

        const rewards = await farmContract.rewards.call();
        const balance = await web3.eth.getBalance(rewards);
        assert.notEqual(balance, 0);
    });

    it("is deployed, pools are added and native is deposited, rewards are earned and are payed out", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 0, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        let pools = await farmContract.getPoolInfo.call();
        assert.equal(adds.length, pools.length);

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        const txFirstDeposit = await farmContract.deposit(0, web3.utils.toWei("1000"));

        truffleAssert.eventEmitted(txFirstDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });

        advanceBlocks(10);

        const firstReward = await farmContract.getPendingNative.call(0, accounts[0]);
        assert.equal(web3.utils.toWei("4000"), firstReward);

        const amount = web3.utils.toWei("10000");
        const tx = await nativeContract.transfer(accounts[1], amount);
        truffleAssert.eventEmitted(tx, 'SwappedForRewards', (ev) => {
            return ev._amount > 0;
        });

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"), { from: accounts[1] });
        const txSecondDeposit = await farmContract.deposit(0, web3.utils.toWei("1000"), { from: accounts[1] });

        truffleAssert.eventEmitted(txSecondDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[1] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });

        advanceBlocks(10);

        const secondReward = await farmContract.getPendingNative.call(0, accounts[0]);
        assert.ok(7200, secondReward);

        const reward = await farmContract.getPendingNative.call(0, accounts[1]);
        assert.equal(web3.utils.toWei("2000"), reward);

        const balanceBeforeWithdraw = await nativeContract.balanceOf(accounts[0]);
        var txWithdraw = await farmContract.withdraw(0, web3.utils.toWei("1000"));

        truffleAssert.eventEmitted(txWithdraw, 'Withdraw', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });

        const balanceAfterWithdraw = await nativeContract.balanceOf(accounts[0]);
        assert.ok(balanceAfterWithdraw > balanceBeforeWithdraw);
    });

    it("is deployed, pools are added and native is deposited, rewards are earned and are payed out", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 2, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        let pools = await farmContract.getPoolInfo.call();
        assert.equal(adds.length, pools.length);

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        const txFirstDeposit = await farmContract.deposit(0, web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txFirstDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });        

        advanceBlocks(10);

        await truffleAssert.reverts(farmContract.withdraw(0, web3.utils.toWei("1000")));        

        let user = await farmContract.userInfo.call(0, accounts[0]);
        const firstLockupStarted = user.lockupStarted;

        assert.ok(firstLockupStarted > 0);

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        const txSecondDeposit = await farmContract.deposit(0, web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txSecondDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        }); 

        advanceBlocks(10);

        user = await farmContract.userInfo.call(0, accounts[0]);
        const secondLockupStarted = user.lockupStarted;

        assert.ok(secondLockupStarted > firstLockupStarted);

        advanceBlocks(10);

        const txThirdDeposit = await farmContract.deposit(0, 0);
        truffleAssert.eventEmitted(txThirdDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == 0;
        }); 

        user = await farmContract.userInfo.call(0, accounts[0]);
        const thirdLockupStarted = user.lockupStarted;

        assert.equal(secondLockupStarted.toString(), thirdLockupStarted.toString());
    });

    it("is deployed, game is finished, and new pool is added, and deposit is added", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 2, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        var tx = await nativeContract.guess("Solution 2", web3.utils.toWei("10"));
        truffleAssert.eventEmitted(tx, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        const add = farmContract.contract.methods.add(native, false, 1000, 0, 2, false).encodeABI();
        await controller.schedule(farm, 0, add, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await truffleAssert.reverts(controller.execute(farm, 0, add, web3.utils.fromAscii(""), web3.utils.fromAscii("")));

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        await truffleAssert.reverts(farmContract.deposit(0, web3.utils.toWei("1000")));
    });

    it("is deployed, game is finished, and rewards are withdrawn", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 0, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        const txDeposit = await farmContract.deposit(0, web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });        

        var txGuess = await nativeContract.guess("Solution 2", web3.utils.toWei("10"));
        truffleAssert.eventEmitted(txGuess, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        const firstReward = await farmContract.getPendingNative.call(0, accounts[0]);
        assert.ok(firstReward > 0);

        advanceBlocks(100);

        const secondReward = await farmContract.getPendingNative.call(0, accounts[0]);
        assert.equal(firstReward.toString(), secondReward.toString());

        const balance = await nativeContract.balanceOf(accounts[0]);

        var txWithdraw = await farmContract.withdraw(0, web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txWithdraw, 'Withdraw', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });

        const newBalance = await nativeContract.balanceOf(accounts[0]);
        assert.equal(balance.add(new BN(secondReward)).add(new BN(web3.utils.toWei("1000"))).toString(), newBalance.toString());
    });

    it("is deployed, and emergency withdraw is called", async () => {
        const controller = await getController();

        const farm = await controller.farm.call();
        assert.notEqual(farm, null);
        const farmContract = await Farm.at(farm);

        const native = await farmContract.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);

        const pair = await addLiquidity(controller, farmContract);
        const adds = [farmContract.contract.methods.add(native, false, 1000, 0, 0, false).encodeABI(), farmContract.contract.methods.add(pair, true, 4000, 0, 0, false).encodeABI()];
        await controller.scheduleBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.executeBatch([farm, farm], [0, 0], adds, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        await nativeContract.increaseAllowance(farm, web3.utils.toWei("1000"));
        const txDeposit = await farmContract.deposit(0, web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txDeposit, 'Deposit', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });   

        const txWithdraw = await farmContract.emergencyWithdraw(0);
        truffleAssert.eventEmitted(txWithdraw, 'EmergencyWithdraw', (ev) => {
            return ev.user == accounts[0] && ev.pid == 0 && ev.amount == web3.utils.toWei("1000");
        });
    });

    function advanceBlocks(numberOfBlocks) {
        for (let i = 0; i < numberOfBlocks; i++) {
            web3.currentProvider.send({ jsonrpc: "2.0", method: "evm_mine", id: 12345 }, () => { });
        }
    }
});