import {ethers, network} from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {ChequeBank} from "../typechain-types";
import {BigNumber, BigNumberish, BytesLike, Signer} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

function createCheque(amount: BigNumberish, validFrom: number, validThru: number, payer: string, payee: string,
                      contract: string, signer: SignerWithAddress) {
    let chequeId = ethers.utils.randomBytes(32);
    let chequeInfo = {chequeId, amount, validFrom, validThru, payee, payer}

    let hashData = ethers.utils.solidityKeccak256(
        ["bytes32", "address", "address", "uint", "address", "uint32", "uint32"],
        [chequeId, payer, payee, amount, contract, validFrom, validThru]
    );
    let sig = signer.signMessage(ethers.utils.arrayify(hashData));
    return {chequeInfo, sig}
}

function createSignOver(counter: number, chequeId: BytesLike, oldPayee: string, newPayee: string, signer: Signer) {
    let signOverInfo = {counter, chequeId, oldPayee, newPayee}
    let hashData = ethers.utils.solidityKeccak256(
        ["bytes4", "uint8", "bytes32", "address", "address"],
        [0xFFFFDEAD, counter, chequeId, oldPayee, newPayee]
    );
    let sig = signer.signMessage(ethers.utils.arrayify(hashData));
    return {signOverInfo, sig}
}

async function mineNBlocks(n: Number) {
    await network.provider.send("hardhat_mine", ["0x" + n.toString(16), "0x0"]);
}

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
        let chequeBank: ChequeBank, deployer: SignerWithAddress, depositAmount: BigNumber
        beforeEach(async function () {
            ({chequeBank, deployer} = await loadFixture(deployFixture));
            depositAmount = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositAmount});
        })

        it("should withdraw ethers", async function () {
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
            await expect(chequeBank.withdraw(0))
                .to.be.revertedWithCustomError(chequeBank, "ZeroAmount");
        });

        it("should revert if withdraw more than account balance", async function () {
            let withdrawAmount = depositAmount.add(1);
            await expect(chequeBank.withdraw(withdrawAmount))
                .to.be.revertedWithCustomError(chequeBank, "NotEnoughBalance")
                .withArgs(depositAmount, withdrawAmount);
        });
    });

    describe("withdrawTo", function () {
        let chequeBank: ChequeBank, deployer: SignerWithAddress, userA: SignerWithAddress, depositAmount: BigNumber
        beforeEach(async function () {
            ({chequeBank, deployer, userA} = await loadFixture(deployFixture));
            depositAmount = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositAmount});
        })

        it("should withdraw ethers", async function () {
            const withdrawAmount = ethers.utils.parseEther("0.8");

            let userABeforeBalance = await ethers.provider.getBalance(userA.address);

            await chequeBank.withdrawTo(withdrawAmount, userA.address);

            let userAAfterBalance = await ethers.provider.getBalance(userA.address);

            const leftAmount = depositAmount.sub(withdrawAmount);
            expect(await ethers.provider.getBalance(chequeBank.address)).equal(leftAmount);
            expect(await chequeBank.addressToBalance(deployer.address)).equal(leftAmount);
            expect(userAAfterBalance.sub(userABeforeBalance)).equal(withdrawAmount);
        });

        it("should revert if withdraw 0 ether", async function () {
            await expect(chequeBank.withdrawTo(0, userA.address))
                .to.be.revertedWithCustomError(chequeBank, "ZeroAmount");
        });

        it("should revert if withdraw more than account balance", async function () {
            let withdrawAmount = depositAmount.add(1);
            await expect(chequeBank.withdrawTo(withdrawAmount, userA.address))
                .to.be.revertedWithCustomError(chequeBank, "NotEnoughBalance")
                .withArgs(depositAmount, withdrawAmount);
        });
    });

    describe("redeem", () => {
        let chequeBank: ChequeBank, deployer: SignerWithAddress, userA: SignerWithAddress, depositAmount: BigNumber,
            cheque: ChequeBank.ChequeStruct, chequeAmount: BigNumber
        beforeEach(async function () {
            ({chequeBank, deployer, userA} = await deployFixture());
            depositAmount = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositAmount});
            chequeAmount = ethers.utils.parseEther("0.2");
            cheque = createCheque(chequeAmount, 0, 0, deployer.address, userA.address, chequeBank.address, deployer);
        })

        it("should redeem the valid cheque", async function () {
            let userABeforeBalance = await ethers.provider.getBalance(userA.address);

            let tx = await chequeBank.connect(userA).redeem(cheque);
            let txReceipt = await tx.wait(1);

            let transactionFee = txReceipt.gasUsed.mul(txReceipt.effectiveGasPrice);
            let userAAfterBalance = await ethers.provider.getBalance(userA.address);

            const leftAmount = depositAmount.sub(chequeAmount);
            expect(await ethers.provider.getBalance(chequeBank.address)).equal(leftAmount);
            expect(await chequeBank.addressToBalance(deployer.address)).equal(leftAmount);
            expect(userAAfterBalance.add(transactionFee).sub(userABeforeBalance)).equal(chequeAmount);
        });

        it("should revert if cheque signature is invalid", async function () {
            // change the amount to make the signature invalid
            cheque.chequeInfo.amount = chequeAmount.add(1);

            await expect(chequeBank.connect(userA).redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "InvalidSignature")
        });

        it("should revert if cheque's validFrom is over validThru and validThru is not 0", async function () {
            await mineNBlocks(5);
            let currBlock = await chequeBank.provider.getBlockNumber();
            cheque = createCheque(chequeAmount, currBlock - 1, currBlock - 2, deployer.address, userA.address, chequeBank.address, deployer);
            await expect(chequeBank.connect(userA).redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "InvalidRedeemTiming")
                .withArgs(currBlock + 1)
        });

        it("should not revert if cheque's validFrom is over validThru but validThru is 0", async function () {
            await mineNBlocks(5);
            let currBlock = await chequeBank.provider.getBlockNumber();
            cheque = createCheque(chequeAmount, currBlock - 1, 0, deployer.address, userA.address, chequeBank.address, deployer);
            await chequeBank.connect(userA).redeem(cheque)
        });

        it("should revert if current block number is over the validThru", async function () {
            let currBlock = await chequeBank.provider.getBlockNumber();
            cheque = createCheque(chequeAmount, 0, currBlock, deployer.address, userA.address, chequeBank.address, deployer);

            await mineNBlocks(5);

            await expect(chequeBank.connect(userA).redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "InvalidRedeemTiming")
                .withArgs(currBlock + 6)
        });

        it("should revert if current block number is under the validFrom", async function () {
            let currBlock = await chequeBank.provider.getBlockNumber();
            cheque = createCheque(chequeAmount, currBlock + 5, currBlock + 15, deployer.address, userA.address, chequeBank.address, deployer);

            await expect(chequeBank.connect(userA).redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "InvalidRedeemTiming")
                .withArgs(currBlock + 1)
        });

        it("should revert if redeem by another user", async function () {
            await expect(chequeBank.redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "Unauthorized")
        });

        it("should revert if the cheque is already redeemed", async function () {
            await chequeBank.connect(userA).redeem(cheque)
            await expect(chequeBank.connect(userA).redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "AlreadyRedeemed")
        });
    });

    describe("revoke", () => {
        let chequeBank: ChequeBank, deployer: SignerWithAddress, userA: SignerWithAddress,
            cheque: ChequeBank.ChequeStruct
        beforeEach(async function () {
            ({chequeBank, deployer, userA} = await deployFixture());
            const depositAmount = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositAmount});
            const chequeAmount = ethers.utils.parseEther("0.2");
            cheque = createCheque(chequeAmount, 0, 0, deployer.address, userA.address, chequeBank.address, deployer);
        })

        it("should reject redeem after revoke", async function () {
            await chequeBank.revoke(cheque.chequeInfo.chequeId)
            await expect(chequeBank.connect(userA).redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "RevokedCheque")
        })

        it("should not affect redeem if NOT revoked by payer", async function () {
            await chequeBank.connect(userA).revoke(cheque.chequeInfo.chequeId)
            await chequeBank.connect(userA).redeem(cheque)
        })

        it("should revert if the cheque is already redeemed", async function () {
            await chequeBank.connect(userA).redeem(cheque)
            await expect(chequeBank.revoke(cheque.chequeInfo.chequeId))
                .to.be.revertedWithCustomError(chequeBank, "AlreadyRedeemed")
        })
    })

    describe("notifySignOver", () => {
        let chequeBank: ChequeBank, deployer: SignerWithAddress, cheque: ChequeBank.ChequeStruct,
            userA: SignerWithAddress, userB: SignerWithAddress, userC: SignerWithAddress

        beforeEach(async function () {
            ({chequeBank, deployer, userA, userB, userC} = await deployFixture());
            const depositAmount = ethers.utils.parseEther("1");
            await chequeBank.deposit({value: depositAmount});
            const chequeAmount = ethers.utils.parseEther("0.2");
            cheque = createCheque(chequeAmount, 0, 0, deployer.address, userA.address, chequeBank.address, deployer);
        })

        it("should refuse redemption after notify sign-over", async () => {
            let chequeId = <BytesLike>cheque.chequeInfo.chequeId;
            let signOver = createSignOver(1, chequeId, userA.address, userB.address, userA);
            await chequeBank.notifySignOver(signOver);
            await expect(chequeBank.connect(userA).redeem(cheque))
                .to.be.revertedWithCustomError(chequeBank, "SignedOverCheque")
        });
    });
})
