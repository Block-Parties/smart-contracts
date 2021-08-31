const { expect } = require("chai")

describe("Sample Exchange", () => {

    let bp
    let ex

    let addrs

    it("Deploys", async () => {
        BP = await ethers.getContractFactory("BlockParties")
        bp = await BP.deploy()

        const Exchange = await ethers.getContractFactory("SampleExchange")
        ex = await Exchange.deploy(bp.address)

        let [_, ...addrs_] = await ethers.getSigners()
        addrs = addrs_

        expect(bp.address).to.not.eq(null)
        expect(ex.address).to.not.eq(null)
    })

    it("Whitelists exchange", async () => {
        await (await bp.whitelistHost(ex.address)).wait()
        expect(await bp.isWhitelisted(ex.address)).to.equal(true)
    })

    it("Creates party", async () => {
        const tx = await ex.createParty("0x5206e78b21Ce315ce284FB24cf05e0585A93B1d9", 0, 200)
        await expect(tx).to.emit(bp, 'Created').withArgs(1, ex.address, 1)
    })

    it("Deposits", async () => {
        const tx = await bp.connect(addrs[0]).deposit(1, { value: 100 })
        await tx.wait()

        expect(await bp.getBalance(1)).to.equal(100)
        expect(await bp.getGigaStake(1, addrs[0].address)).to.equal('' + (10 ** 9))
    })

    it("Deposits again", async () => {
        const tx = await bp.connect(addrs[1]).deposit(1, { value: 100 })
        await tx.wait()

        expect(await bp.getBalance(1)).to.equal(200)
        expect(await bp.getGigaStake(1, addrs[1].address)).to.equal('' + (5 * 10 ** 8))
    })

    it("Prevents overwithdrawal", async () => {
        await expect(bp.withdraw(1, 200)).to.be.revertedWith("The amount requested exceeds the sender's stake")
    })


    it("Allows withdrawals", async () => {
        const preBalance = await addrs[0].getBalance()
        const tx = await bp.connect(addrs[0]).withdraw(1, 100)
        const receipt = await tx.wait()
        const postBalance = await addrs[0].getBalance()

        expect(await bp.getBalance(1)).to.equal(100)
        expect(postBalance).to.equal('' + (preBalance.add(100).sub(receipt.effectiveGasPrice.mul(receipt.cumulativeGasUsed))))
    })

    it("Simulates buy and sell", async () => {
        const tx = await ex.buy(1)
        await tx.wait()

        const t = await ex.sell(1)
        await t.wait()

        expect(await bp.getBalance(1)).to.equal(100)
    })
})
