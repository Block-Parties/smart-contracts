const { expect } = require("chai")

describe("Wyvern Exchange", () => {

    let bp
    let ex

    let addrs

    it("Deploys", async () => {
        BP = await ethers.getContractFactory("BlockParties")
        bp = await BP.deploy()

        const Exchange = await ethers.getContractFactory("WyvernExchange")
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
        const tx = await ex.createParty("0x5206e78b21Ce315ce284FB24cf05e0585A93B1d9", 0, 200, 300)
        await tx.wait()
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

    // TODO: I'm not sure how to write a test for this without pulling in tons of other contracts...
    // it("Simulates buy and sell", async () => {

    //     buy_data = {
    //         addrs: [
    //             '0x5206e78b21ce315ce284fb24cf05e0585a93b1d9',
    //             '0x60f0535cdb529b13bcdf4411e4e594bd67cf2436',
    //             '0x895eece103e6028426759366f1b1d70900ecbe90',
    //             '0x0000000000000000000000000000000000000000',
    //             '0xbb5bec579a50404dbc1d693d01432fcf064e8849',
    //             '0x0000000000000000000000000000000000000000',
    //             '0x0000000000000000000000000000000000000000',
    //             '0x5206e78b21ce315ce284fb24cf05e0585a93b1d9',
    //             '0x895eece103e6028426759366f1b1d70900ecbe90',
    //             '0x0000000000000000000000000000000000000000',
    //             '0x5b3256965e7c3cf26e11fcaf296dfc8807c01073',
    //             '0xbb5bec579a50404dbc1d693d01432fcf064e8849',
    //             '0x0000000000000000000000000000000000000000',
    //             '0x0000000000000000000000000000000000000000'
    //         ],
    //         uints: [
    //             '0x8ca',
    //             '0x0',
    //             '0x0',
    //             '0x0',
    //             '0x3e2c284391c0000',
    //             '0x0',
    //             '0x6119bcca',
    //             '0x0',
    //             '0xd785b3fec37efc8b9580491fe2a10542d111f399517400849521d399a7d87f6d',
    //             '0x8ca',
    //             '0x0',
    //             '0x0',
    //             '0x0',
    //             '0x3e2c284391c0000',
    //             '0x0',
    //             '0x61160d8d',
    //             '0x0',
    //             '0x36e31f8ef1aac1a29fe716cfc585a30c23bf51fd4e8f10aa2e5df41fdbbf90ec'
    //         ],
    //         feeMethodsSidesKindsHowToCalls: [
    //             1, 0, 0, 0,
    //             1, 1, 0, 0
    //         ],
    //         calldataBuy: '0x23b872dd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060f0535cdb529b13bcdf4411e4e594bd67cf24360000000000000000000000000000000000000000000000000000000000000005',
    //         calldataSell: '0x23b872dd000000000000000000000000895eece103e6028426759366f1b1d70900ecbe9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005',
    //         replacementPatternBuy: '0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
    //         replacementPatternSell: '0x000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000',
    //         staticExtradataBuy: '0x',
    //         staticExtradataSell: '0x',
    //         vs: [27, 27],
    //         rssMetadata: [
    //             '0xc6418b4abd0c3b8416ef086c841bcae1094a794a3d87ecc39adb78022647070c',
    //             '0x41b44ffc55d0e361aa70dbbce976c31b90b50643392d754e44ec0e2af0efbd26',
    //             '0xc6418b4abd0c3b8416ef086c841bcae1094a794a3d87ecc39adb78022647070c',
    //             '0x41b44ffc55d0e361aa70dbbce976c31b90b50643392d754e44ec0e2af0efbd26',
    //             '0x0000000000000000000000000000000000000000000000000000000000000000'
    //         ]
    //     }

    //     // const tx = await ex.buy(1, 100, buy_data)
    //     const tx = await ex.buy(1)
    //     await tx.wait()

    //     const t = await ex.sell(1)
    //     await t.wait()

    //     expect(await bp.getBalance(1)).to.equal(100)
    // })
})
