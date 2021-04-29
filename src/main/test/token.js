const Controller = artifacts.require("GuessItController");
const Token = artifacts.require("GuessItToken");
const Rewards = artifacts.require("GuessItRewards");
const Router = artifacts.require("IPancakeRouter02");
const Factory = artifacts.require("IPancakeFactory");
const Pair = artifacts.require("IPancakePair");

contract("GuessItController", async accounts => {
    const truffleAssert = require('truffle-assertions');
    const BN = web3.utils.BN;

    async function getController() {
        return await Controller.new('0xa8593E8d99098e3904F91F993b3216c56713b3cA', '0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0', 0, ['0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0']);
    }

    async function getNativeContract() {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        return await Token.at(native);
    }

    async function startNewGame(nativeContract, addLiquidity = true, puzzle = "puzzle", solutions = ["solution", "Solution"], guessPrice = "10") {
        if (addLiquidity) {
            await nativeContract.addLiquidity(accounts[0], { value: web3.utils.toWei("20") });
        }
        await nativeContract.newGame(web3.utils.asciiToHex(puzzle), solutions.map(web3.utils.asciiToHex), web3.utils.toWei(guessPrice));
    }

    async function getSomeTokens(nativeContract) {
        const router = await nativeContract.pancakeRouter.call();
        assert.notEqual(router, null);
        const routerContract = await Router.at(router);

        const factory = await routerContract.factory.call();
        assert.notEqual(factory, null);
        const factoryContract = await Factory.at(factory);

        const wbnb = await routerContract.WETH.call();
        const pair = await factoryContract.getPair.call(nativeContract.address, wbnb);
        const pairContract = await Pair.at(pair);
        const balance =  await pairContract.balanceOf(accounts[0]);
        const balanceToRemove = balance.div(new BN("10"));

        await pairContract.approve(router, balanceToRemove);
        await routerContract.removeLiquidityETH(nativeContract.address, balanceToRemove, 0, 0, accounts[0], Date.now());
    }

    // it("is correctly deployed", async () => {
    //     const controller = await getController();

    //     const native = await controller.native.call();
    //     assert.notEqual(native, null);
    //     const nativeContract = await Token.at(native);

    //     const router = await nativeContract.pancakeRouter.call();
    //     assert.notEqual(router, null);

    //     const rewards = await nativeContract.rewards.call();
    //     assert.notEqual(rewards, null);

    //     const nativeExcludedFromFee = await nativeContract.isExcludedFromFee.call(native);
    //     assert.ok(nativeExcludedFromFee);

    //     const rewardsExcludedFromFee = await nativeContract.isExcludedFromFee.call(rewards);
    //     assert.ok(rewardsExcludedFromFee);
    // });

    // it("is deployed and not enough liquidity is provided", async () => {
    //     const nativeContract = await getNativeContract();

    //     await truffleAssert.reverts(nativeContract.addLiquidity(accounts[0], { value: web3.utils.toWei("10") }));
    // });

    // it("is not allowed to start new game without adding liquidity", async () => {
    //     const nativeContract = await getNativeContract();
    //     await truffleAssert.reverts(startNewGame(nativeContract, false));
    // });

    // it("is deployed and liquidity is added", async () => {
    //     const nativeContract = await getNativeContract();

    //     await nativeContract.addLiquidity(accounts[0], { value: web3.utils.toWei("20") });

    //     const totalSupply = await nativeContract.totalSupply.call();
    //     assert.equal(totalSupply, web3.utils.toWei("10000000"));
    // });

    // it("is account excluded/included from fee", async () => {
    //     const controller = await getController();

    //     const native = await controller.native.call();
    //     assert.notEqual(native, null);
    //     const nativeContract = await Token.at(native);

    //     const excluded = nativeContract.contract.methods.excludeFromFee(accounts[0]).encodeABI();
    //     await controller.schedule(native, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
    //     await controller.execute(native, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

    //     let isExcluded = await nativeContract.isExcludedFromFee.call(accounts[0]);
    //     assert.ok(isExcluded);

    //     const included = nativeContract.contract.methods.includeInFee(accounts[0]).encodeABI();
    //     await controller.schedule(native, 0, included, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
    //     await controller.execute(native, 0, included, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

    //     isExcluded = await nativeContract.isExcludedFromFee.call(accounts[0]);
    //     assert.ok(!isExcluded);
    // });

    // it("is deployed and a new game is started", async () => {
    //     const nativeContract = await getNativeContract();

    //     const newPrice = web3.utils.toWei("10");
    //     await startNewGame(nativeContract, guessPrice = newPrice);

    //     const game = await nativeContract.getGame.call();
    //     assert.equal(game.finished, false);

    //     const currentPrice = await nativeContract.getPrice.call();
    //     assert.equal(currentPrice, newPrice);
    // });

    // it("is not allowed to start a new game when there is a game started", async () => {
    //     const nativeContract = await getNativeContract();

    //     await startNewGame(nativeContract,);
    //     await truffleAssert.reverts(startNewGame(nativeContract, false));
    // });

    // it("is allowed to set the price after the game is started", async () => {
    //     const controller = await getController();

    //     const native = await controller.native.call();
    //     assert.notEqual(native, null);
    //     const nativeContract = await Token.at(native);

    //     await startNewGame(nativeContract);
    //     const newPrice = web3.utils.toWei("30");

    //     const func = nativeContract.contract.methods.setPrice(newPrice).encodeABI();
    //     await controller.schedule(native, 0, func, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
    //     await controller.execute(native, 0, func, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

    //     const currentPrice = await nativeContract.getPrice.call();
    //     assert.equal(currentPrice, newPrice);
    // });

    // it("is deployed, a new game is started and not enough tokens are provided for guessing", async () => {
    //     const nativeContract = await getNativeContract();

    //     await startNewGame(nativeContract);
    //     await truffleAssert.reverts(nativeContract.guess("solution 2", 0));
    // });

    it("is deployed, a new game is started and someone tried to guess unsuccessfully", async () => {
        const nativeContract = await getNativeContract();

        await startNewGame(nativeContract);
        await getSomeTokens(nativeContract);

        const totalSupply = await nativeContract.totalSupply.call();
        const rewardsPercentage = await nativeContract.rewardsPercentage.call();

        var price = web3.utils.toWei("10");

        var tokenBalance = await nativeContract.balanceOf(accounts[0]);
        assert.ok(tokenBalance > price);

        console.log("price: " + price);
        console.log("balance: " + tokenBalance);

        var tx = await nativeContract.guess("solution 2", price);
        truffleAssert.eventEmitted(tx, 'Guessed', (ev) => {
            return ev._guessed === false;
        });

        const newTotalSupply = await nativeContract.totalSupply.call();
        assert.equal(newTotalSupply, totalSupply - price * rewardsPercentage / 1000);        

        const game = await nativeContract.getGame.call();
        assert.equal(game.finished, false);

        const rewards = await nativeContract.rewards.call();
        const balance = await web3.eth.getBalance(rewards);
        console.log("balance: " + balance);
        //assert.notEqual(balance, 0);
    });
});