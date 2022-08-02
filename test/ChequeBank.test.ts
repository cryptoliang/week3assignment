import {ethers} from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";

describe("ChequeBank", function () {
    async function deployFixture() {
        const chequeBankFactory = await ethers.getContractFactory("ChequeBank");
        const chequeBank = await chequeBankFactory.deploy();
        const [deployer, userA, userB, userC] = await ethers.getSigners();
        return {chequeBank, deployer, userA, userB, userC};
    }

    describe("deposit", function () {
        it("should deposit ethers", async function () {
            const {chequeBank, deployer} = await loadFixture(deployFixture);
            let depositAmount = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositAmount});
            expect(await chequeBank.addressToBalance(deployer.address)).equal(depositAmount);
            expect(await ethers.provider.getBalance(chequeBank.address)).equal(depositAmount);
        });

        it("should revert if deposit 0 ether", async function () {
            const {chequeBank} = await loadFixture(deployFixture);
            await expect(chequeBank.deposit()).to.be.revertedWithCustomError(chequeBank, "ZeroAmount");
        });
    });

    describe("withdraw", function () {
        it("should withdraw ethers", async function () {
            const {chequeBank, deployer} = await loadFixture(deployFixture);
            const depositAmount = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositAmount});

            const withdrawAmount = ethers.utils.parseEther("0.8");
            let deployerBeforeBalance = await ethers.provider.getBalance(deployer.address);

            let tx = await chequeBank.withdraw(withdrawAmount);
            let txReceipt = await tx.wait(1);

            let transactionFee = txReceipt.gasUsed.mul(txReceipt.effectiveGasPrice);
            let deployerAfterBalance = await ethers.provider.getBalance(deployer.address);

            const leftAmount = depositAmount.sub(withdrawAmount);
            expect(await ethers.provider.getBalance(chequeBank.address)).equal(leftAmount);
            expect(await chequeBank.addressToBalance(deployer.address)).equal(leftAmount);
            expect(deployerAfterBalance.add(transactionFee).sub(deployerBeforeBalance)).equal(withdrawAmount);
        });

        it("should revert if withdraw 0 ether", async function () {
            const {chequeBank} = await loadFixture(deployFixture);
            await expect(chequeBank.withdraw(0))
                .to.be.revertedWithCustomError(chequeBank, "ZeroAmount");
        });

        it("should revert if withdraw more than account balance", async function () {
            const {chequeBank} = await loadFixture(deployFixture);
            await expect(chequeBank.withdraw(1))
                .to.be.revertedWithCustomError(chequeBank, "NotEnoughBalance")
                .withArgs(0, 1);
        });
    });
})
