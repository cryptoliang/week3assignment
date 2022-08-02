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
            let depositValue = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositValue});
            expect(await chequeBank.addressToBalance(deployer.address)).equal(depositValue)
            expect(await ethers.provider.getBalance(chequeBank.address)).equal(depositValue)
        });

        it("should revert if deposit 0 ether", async function () {
            const {chequeBank} = await loadFixture(deployFixture);
            await expect(chequeBank.deposit()).to.be.revertedWithCustomError(chequeBank, "ZeroAmount");
        });
    });
})
