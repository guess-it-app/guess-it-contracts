const Controller = artifacts.require("GuessItController");
const Token = artifacts.require("GuessItToken");
const Rewards = artifacts.require("GuessItRewards");
const Router = artifacts.require("IPancakeRouter02");
const Factory = artifacts.require("IPancakeFactory");

contract("GuessItController", async accounts => {
    const truffleAssert = require('truffle-assertions');
    const BN = web3.utils.BN;

    async function getController() {
        return await Controller.new('0xC930dA3fB1205E72AF54b7305E1fD030C5118c89', '0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0', 0, ['0x82EC43c1b93E3aDeE158D81e9C1eABA89598Edc0']);
    }

    async function getNativeContract() {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        return await Token.at(native);
    }

    async function startNewGame(nativeContract, puzzle = "puzzle", solutions = ["solution 1", "solution 2"], guessPrice = "10") {
        await nativeContract.newGame(web3.utils.keccak256(puzzle), solutions.map(web3.utils.keccak256), web3.utils.toWei(guessPrice));
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

        await nativeContract.approve(router, web3.utils.toWei("10000"));
        await routerContract.addLiquidityETH(nativeContract.address, web3.utils.toWei("10000"), web3.utils.toWei("10000"), web3.utils.toWei("1"), accounts[0], Date.now(), { value: web3.utils.toWei("1") });
    }

    it("is correctly deployed", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        const router = await nativeContract.pancakeRouter.call();
        assert.notEqual(router, null);

        const rewards = await nativeContract.rewards.call();
        assert.notEqual(rewards, null);

        const nativeExcludedFromFee = await nativeContract.isExcludedFromFee.call(native);
        assert.ok(nativeExcludedFromFee);

        const rewardsExcludedFromFee = await nativeContract.isExcludedFromFee.call(rewards);
        assert.ok(rewardsExcludedFromFee);
    });

    it("is account excluded/included from fee", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        const excluded = nativeContract.contract.methods.excludeFromFee(accounts[0]).encodeABI();
        await controller.schedule(native, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.execute(native, 0, excluded, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        let isExcluded = await nativeContract.isExcludedFromFee.call(accounts[0]);
        assert.ok(isExcluded);

        const included = nativeContract.contract.methods.includeInFee(accounts[0]).encodeABI();
        await controller.schedule(native, 0, included, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.execute(native, 0, included, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        isExcluded = await nativeContract.isExcludedFromFee.call(accounts[0]);
        assert.ok(!isExcluded);
    });

    it("is deployed and a new game is started", async () => {
        const nativeContract = await getNativeContract();

        const newPrice = web3.utils.toWei("10");
        await startNewGame(nativeContract, guessPrice = newPrice);

        const game = await nativeContract.getGame.call();
        assert.equal(game.finished, false);

        const currentPrice = await nativeContract.getPrice.call();
        assert.equal(currentPrice, newPrice);
    });

    it("is not allowed to start a new game when there is a game started", async () => {
        const nativeContract = await getNativeContract();

        await startNewGame(nativeContract,);
        await truffleAssert.reverts(startNewGame(nativeContract));
    });

    it("is allowed to set the price after the game is started", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);
        const newPrice = web3.utils.toWei("30");

        const func = nativeContract.contract.methods.setPrice(newPrice).encodeABI();
        await controller.schedule(native, 0, func, web3.utils.fromAscii(""), web3.utils.fromAscii(""), 0);
        await controller.execute(native, 0, func, web3.utils.fromAscii(""), web3.utils.fromAscii(""));

        const currentPrice = await nativeContract.getPrice.call();
        assert.equal(currentPrice, newPrice);
    });

    it("is deployed, a new game is started and not enough tokens are provided for guessing", async () => {
        const nativeContract = await getNativeContract();

        await startNewGame(nativeContract);
        await truffleAssert.reverts(nativeContract.guess("solution 2", 0));
    });

    it("is deployed, a new game is started and someone tried to guess unsuccessfully", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);
        await addLiquidity(controller, nativeContract);

        const totalSupply = await nativeContract.totalSupply.call();

        var price = web3.utils.toWei("10");

        var tokenBalance = await nativeContract.balanceOf(accounts[0]);
        assert.ok(tokenBalance > price);

        var tx = await nativeContract.guess("solution 3", price);
        truffleAssert.eventEmitted(tx, 'Guessed', (ev) => {
            return ev._guessed === false;
        });

        const newTotalSupply = await nativeContract.totalSupply.call();
        assert.notEqual(newTotalSupply, totalSupply);

        const game = await nativeContract.getGame.call();
        assert.equal(game.finished, false);

        truffleAssert.eventEmitted(tx, 'SwappedForRewards', (ev) => {
            return ev._amount > 0;
        });

        const rewards = await nativeContract.rewards.call();
        const balance = await web3.eth.getBalance(rewards);
        assert.notEqual(balance, 0);
    });

    it("is deployed, a new game is started and someone guessed the puzzle", async () => {
        const nativeContract = await getNativeContract();

        await startNewGame(nativeContract);

        var price = web3.utils.toWei("10");
        var tx = await nativeContract.guess("Solution 2", price);
        truffleAssert.eventEmitted(tx, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        const game = await nativeContract.getGame.call();
        assert.ok(game.finished);
    });

    it("is deployed, a new game is started and tokens are send", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);
        await addLiquidity(controller, nativeContract);

        const balanceOfFirstAccount = await nativeContract.balanceOf(accounts[0]);

        const amount = web3.utils.toWei("10");
        const tx = await nativeContract.transfer(accounts[1], amount);

        const balanceOfSecondAccount = await nativeContract.balanceOf(accounts[1]);

        assert.ok(balanceOfSecondAccount > 0);

        const newBalanceOfFirstAccount = await nativeContract.balanceOf(accounts[0]);

        assert.equal(newBalanceOfFirstAccount.toString(), balanceOfFirstAccount.sub(new BN(amount)).toString());

        truffleAssert.eventEmitted(tx, 'SwappedForRewards', (ev) => {
            return ev._amount > 0;
        });

        const rewards = await nativeContract.rewards.call();
        const balance = await web3.eth.getBalance(rewards);
        assert.notEqual(balance, 0);
    });

    it("is deployed, a new game is started and withdraw is called before puzzle is guessed", async () => {
        const nativeContract = await getNativeContract();

        await startNewGame(nativeContract);

        var price = web3.utils.toWei("10");
        var tx = await nativeContract.guess("Solution 3", price);
        truffleAssert.eventEmitted(tx, 'Guessed', (ev) => {
            return ev._guessed === false;
        });

        await truffleAssert.reverts(nativeContract.withdraw(web3.utils.toWei("1000")));
    });

    it("is deployed, a new game is started, someone guessed the puzzle and rewards are claimed", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);
        
        await startNewGame(nativeContract);
        await addLiquidity(controller, nativeContract);

        var price = web3.utils.toWei("10");
        var txGuess = await nativeContract.guess("Solution 2", price);
        truffleAssert.eventEmitted(txGuess, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        var currentBalance = await web3.eth.getBalance(accounts[0]);        

        var rewards = await nativeContract.claimableRewards.call(web3.utils.toWei("1000"));
        assert.notEqual(0, rewards);

        const txWithdraw = await nativeContract.withdraw(web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txWithdraw, 'Withdrawn', (ev) => {
            return ev._to === accounts[0] && ev._amount.toString() === rewards.toString();
        });

        var newBalance = await web3.eth.getBalance(accounts[0]);
        assert.notEqual(newBalance, currentBalance);
    });

    it("is deployed, a new game is started, someone guessed the puzzle, guesser is withdrawing twice", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);
        await addLiquidity(controller, nativeContract);

        var price = web3.utils.toWei("10");
        var txGuess = await nativeContract.guess("Solution 2", price);
        truffleAssert.eventEmitted(txGuess, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        var fistClaimableRewards = await nativeContract.claimableRewards.call(web3.utils.toWei("1000"));
        const txWithdrawFirst = await nativeContract.withdraw(web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txWithdrawFirst, 'Withdrawn', (ev) => {
            return ev._to === accounts[0] && ev._amount.toString() === fistClaimableRewards.toString();
        });

        var secondClaimableRewards = await nativeContract.claimableRewards.call(web3.utils.toWei("1000"));

        assert.ok(fistClaimableRewards > secondClaimableRewards);

        const txWithdrawSecond = await nativeContract.withdraw(web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txWithdrawSecond, 'Withdrawn', (ev) => {
            return ev._to === accounts[0] && ev._amount.toString() === secondClaimableRewards.toString();
        });
    });

    it("is deployed, a new game is started, someone guessed the puzzle, transfer occurred to other account and rewards are claimed", async () => {
        const controller = await getController();

        const native = await controller.native.call();
        assert.notEqual(native, null);
        const nativeContract = await Token.at(native);

        await startNewGame(nativeContract);
        await addLiquidity(controller, nativeContract);

        var price = web3.utils.toWei("10");
        var txGuess = await nativeContract.guess("Solution 2", price);
        truffleAssert.eventEmitted(txGuess, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        var rewards = await nativeContract.claimableRewards.call(web3.utils.toWei("1000"));
        assert.notEqual(0, rewards);

        const amount = web3.utils.toWei("1000");
        await nativeContract.transfer(accounts[1], amount);

        const txWithdraw = await nativeContract.withdraw(web3.utils.toWei("1000"));
        truffleAssert.eventEmitted(txWithdraw, 'Withdrawn', (ev) => {
            return ev._to === accounts[0] && ev._amount.toString() === rewards.toString();
        });

        var secondAccountRewards = await nativeContract.claimableRewards.call(web3.utils.toWei("1000"), { from: accounts[1] });
        assert.notEqual(0, secondAccountRewards);
    });

    it("is deployed and mint is not allowed", async () => {
        const nativeContract = await getNativeContract();

        await truffleAssert.reverts(nativeContract.mint(accounts[0], web3.utils.toWei("1")));
    });

    it("is deployed and direct rewards transfer is not allowed", async () => {
        const nativeContract = await getNativeContract();

        await startNewGame(nativeContract);

        var price = web3.utils.toWei("10");
        var txGuess = await nativeContract.guess("Solution 2", price);
        truffleAssert.eventEmitted(txGuess, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        const rewards = await nativeContract.rewards.call();
        assert.notEqual(rewards, null);
        const rewardsContract = await Rewards.at(rewards);

        await truffleAssert.reverts(rewardsContract.transferRewards(accounts[0], 1));
    });

    it("is not allowed to set owner settings without timelock", async () => {
        const nativeContract = await getNativeContract();

        await truffleAssert.reverts(nativeContract.setRewardsPercentage(500));
    });

    it("is deployed, game is finished and everything is viewable", async () => {
        const nativeContract = await getNativeContract();

        await startNewGame(nativeContract);

        var price = web3.utils.toWei("10");
        var txGuess = await nativeContract.guess("Solution 2", price);
        truffleAssert.eventEmitted(txGuess, 'Guessed', (ev) => {
            return ev._guessed === true;
        });

        const viewable = await nativeContract.getViewablePuzzleShare.call();
        assert.equal(viewable, 1000);
    });
});