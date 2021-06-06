const Controller = artifacts.require("GuessItController");
const Token = artifacts.require("GuessItToken");
const Rewards = artifacts.require("GuessItRewards");
const Router = artifacts.require("IPancakeRouter02");
const Factory = artifacts.require("IPancakeFactory");
const Game = artifacts.require("GuessItGame");

contract("GuessItController", async accounts => {
    const truffleAssert = require('truffle-assertions');
    const BN = web3.utils.BN;

    async function getController() {
        return await Controller.deployed();
    }

    async function startNewGame(swapContract, nativeContract, solutions = ["solution 1", "solution 2"], guessPrice = "10") {
        return await Game.new(swapContract, nativeContract, solutions.map(web3.utils.keccak256), web3.utils.toWei(guessPrice));
    }

    async function addLiquidity(controller, nativeContract) {
        const router = await nativeContract.pancakeRouter.call();
        assert.notEqual(router, null);
        const routerContract = await Router.at(router);

        const factory = await routerContract.factory.call();
        assert.notEqual(factory, null);
        const factoryContract = await Factory.at(factory);

        const wbnb = await routerContract.WETH.call();
        await factoryContract.createPair(nativeContract.address, wbnb);
        const pair = await factoryContract.getPair.call(nativeContract.address, wbnb);

        let excluded = nativeContract.contract.methods.excludeFromFee(pair).encodeABI();
        await controller.schedule(nativeContract.address, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.execute(nativeContract.address, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        await nativeContract.approve(router, web3.utils.toWei("100000"));
        await routerContract.addLiquidityETH(nativeContract.address, web3.utils.toWei("100000"), web3.utils.toWei("100000"), web3.utils.toWei("1"), accounts[0], Date.now(), { value: web3.utils.toWei("1") });
    }

    it("is correctly deployed", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        const router = await nativeContract.pancakeRouter.call();
        assert.notEqual(router, null);
        
        const game = await startNewGame(router, native);
        assert.notEqual(game, null);  
    });

    it("is not guessed correctly", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);
        
        const router = await nativeContract.pancakeRouter.call();
        assert.notEqual(router, null);
        
        const gameContract = await startNewGame(router, native);
        assert.notEqual(gameContract, null);  

        await nativeContract.approve(gameContract.address, web3.utils.toWei("10000"));
        var price = web3.utils.toWei("10");
        var tx = await gameContract.guess("solution 3", price);
        truffleAssert.eventEmitted(tx, 'Guessed', (ev) => {
            return ev._guessed === false;
        });

        var balance = await nativeContract.balanceOf.call(gameContract.address);
        assert.equal(price, balance);
    });

    it("is not guessed correctly and swap", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);
        
        const router = await nativeContract.pancakeRouter.call();
        assert.notEqual(router, null);
        
        const gameContract = await startNewGame(router, native);
        assert.notEqual(gameContract, null);  

        await nativeContract.approve(gameContract.address, web3.utils.toWei("10000"));
        var price = web3.utils.toWei("10");
        var tx = await gameContract.guess("solution 3", price);
        truffleAssert.eventEmitted(tx, 'Guessed', (ev) => {
            return ev._guessed === false;
        });

        var balance = await nativeContract.balanceOf.call(gameContract.address);
        assert.equal(price, balance);

        await addLiquidity(controller, nativeContract);

        await gameContract.swap();
        const bnb = await web3.eth.getBalance(gameContract.address);
        assert.notEqual(bnb, 0);
    });

    it("is guessed correctly and rewards are withdrawn", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);
        
        const router = await nativeContract.pancakeRouter.call();
        assert.notEqual(router, null);
        
        const gameContract = await startNewGame(router, native);
        assert.notEqual(gameContract, null);  

        await nativeContract.approve(gameContract.address, web3.utils.toWei("10000"));
        var price = web3.utils.toWei("10");
        var tx1 = await gameContract.guess("solution 3", price);
        truffleAssert.eventEmitted(tx1, 'Guessed', (ev) => {
            return ev._guessed === false;
        });

        var balance = await nativeContract.balanceOf.call(gameContract.address);
        assert.equal(price, balance);

        await addLiquidity(controller, nativeContract);

        var tx4 = await gameContract.swap();
        truffleAssert.eventEmitted(tx4, 'SwappedForRewards', (ev) => {
            return ev._amount > 0;
        });
        const bnb1 = await web3.eth.getBalance(gameContract.address);
        assert.notEqual(bnb1, 0);

        var tx2 = await gameContract.guess("solution 1", price);
        truffleAssert.eventEmitted(tx2, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        await truffleAssert.reverts(gameContract.withdraw({ from: accounts[1] }));

        var tx3 = await gameContract.withdraw();
        truffleAssert.eventEmitted(tx3, 'SwappedForRewards', (ev) => {
            return ev._amount > 0;
        });
        truffleAssert.eventEmitted(tx3, 'Withdrawn', (ev) => {
            return ev._amount > bnb1;
        });
    });
});