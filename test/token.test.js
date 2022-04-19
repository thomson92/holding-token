// require
const HoldToken = artifacts.require("./HoldToken.sol");
var chai = require("chai");
// var assert = chai.assert;    // Using Assert style
var should = chai.should(); // Using Should style

const BigNumber = require('bignumber.js');


BigInt.prototype.toJSON = function() {       
  return this.toString()
}

contract("HoldToken", (accounts) => {
  const _tokenName = "test2";
  const _initialSupply = 1000000000000e18;
  const devFee = 0.02;
  const holdersFee = 0.06;

  const recipients = [
    "0x844A333e7e4707F4863CF7Efae8754A282018427",
    "0x8d6daFb9860c5e021Fa42dFa951505db81a1972a",
    "0x6a29Ea7c8AF0455F02148CE1B5CcD1C2BA4E0006",
    "0x56bd72E8c1bCC23257E9382134FCB1023773374a"
  ]

  const isAnyAddressPresentInTier = async (tier) => {
    const addresses = await this.HoldToken.getTierAddresses(tier);

    return addresses;
  }

  const tierChecker = async (userFunds) => {
    if(userFunds < 31400001 * 10 ** 18) return 0;
    if(userFunds >= 31400001 * 10 ** 18 && userFunds < 314000001 * 10 ** 18) return 1;
    if(userFunds >= 314000001 * 10 ** 18 && userFunds < 3140000001 * 10 ** 18) return 2;
    if(userFunds >= 3140000001 * 10 ** 18 && userFunds < 31400000001 * 10 ** 18) return 3;
    return 4; // >= 31400000001
  }

  const transfer = async (address, amount) => {
    await this.HoldToken.transfer(address, amount);
  }

  const fakeLP_transfer = async () => {
    const lpFunds = new BigNumber(_initialSupply * 0.49);
    await this.HoldToken.transfer("0x199C8b1729b823cCE45b72c4E68721b8C58dab96", lpFunds);
  }

  before(async () => {
    this.HoldToken = await HoldToken.deployed();
    this.creatorAddress = await this.HoldToken.getOwner();
    await fakeLP_transfer();
  });

  it("deployed successfully", async () => {
    const address = await this.HoldToken.address;
    assert.notEqual(address, 0x0);
    assert.notEqual(address, "");
    assert.notEqual(address, null);
    assert.notEqual(address, undefined);
  });

  it("should have correct metadata", async () => {
    const name = await this.HoldToken.name();
    // name.should.equal();
    assert.equal(name, _tokenName);
  });

  it("should have proper total supply", async () => {
    const totalSupply = await this.HoldToken.totalSupply();

    assert.equal(totalSupply, _initialSupply);
  });

  it("should burn 48% of supply", async () => {
    const deadWalletSupply = await this.HoldToken.balanceOf('0x000000000000000000000000000000000000dEaD');

    assert.equal(deadWalletSupply, _initialSupply * 0.49);
  });

  it("should send 2% of total supply to token creator wallet", async () => {
    const creatorFunds = new BigNumber(await this.HoldToken.balanceOf(this.creatorAddress));
    const expectedFunds = new BigNumber('20000000000000000000000000000');

    expect(creatorFunds).to.eql(expectedFunds);
  });

  it("should increment transfer counter", async () => {
    const recipient = "0x65F9Fdd2030C8b9D531800CC77149BBe1AfEc49b";
    const amount = 1000;

    await this.HoldToken.transfer(recipient, amount);
    const count = BigInt(await this.HoldToken.transferCounter());

    expect(count).to.be.equal(BigInt(2));

    await this.HoldToken.transfer(recipient, amount);
    const count2 = BigInt(await this.HoldToken.transferCounter());

    expect(count2).to.be.equal(BigInt(3));
  });

  it("should burn 2% fee on transfer", async () => {
    const recipient = "0x65F9Fdd2030C8b9D531800CC77149BBe1AfEc49b";
    const amount = 100000000;
    const feeForDeadWallet = amount * 0.02;

    let deadWalletBalanceBeforeFee = BigInt(await this.HoldToken.balanceOf('0x000000000000000000000000000000000000dEaD'));
    // const expectedDeadWalletBalanceAfterFee = deadWalletBalanceBeforeFee + amount;

    await this.HoldToken.transfer(recipient, amount);

    const deadWalletBalanceAfterFee = BigInt(await this.HoldToken.balanceOf('0x000000000000000000000000000000000000dEaD'));
    deadWalletBalanceBeforeFee += BigInt(feeForDeadWallet);

    expect(deadWalletBalanceAfterFee).to.be.equal(deadWalletBalanceBeforeFee);
  });

  it("should assign dev wallet to tier 3 after first transfer", async () => {
    const amount = new BigNumber(10000000e18);

    await this.HoldToken.transfer(recipients[1], amount);
    const adrs = await this.HoldToken.getTierAddresses(3);

    expect(adrs.includes(this.creatorAddress)).to.be.true;
  });

  it("should transfer 2% fee to creator (dev wallet) + 6% holder fee", async () => {
    const amount = new BigNumber(100);
    const feeForDevWallet = amount.multipliedBy(holdersFee + devFee);
    const creatorBalance_beforeFee = new BigNumber(await this.HoldToken.balanceOf(this.creatorAddress));

    const expectedDevBalance = creatorBalance_beforeFee.plus(feeForDevWallet).minus(amount);

    await this.HoldToken.transfer(recipients[1], amount);

    const creatorBalance_afterFee = new BigNumber(await this.HoldToken.balanceOf(this.creatorAddress));

    expect(creatorBalance_afterFee).to.be.eql(expectedDevBalance);
  });

  it("should assign recipient to tier 1 after transfer", async () => {
    const amount = new BigNumber(351680000e18);
    
    const tier1_BeforeTransfer = await this.HoldToken.getTierAddresses(1);

    await this.HoldToken.transfer(recipients[3], amount);

    const tier1_AfterTransfer = await this.HoldToken.getTierAddresses(1);
    const qwe = new BigNumber(await this.HoldToken.balanceOf(recipients[3]));

    console.log(qwe.toString(), tierChecker(qwe));
    
    expect(tier1_BeforeTransfer.length === 0).to.be.true;
    expect(tier1_AfterTransfer.includes(recipients[3])).to.be.true;
  });

  it("should move user from tier 3 to 0", async () => {
    const amount = new BigNumber(19000000000e18);
    
    const tier3_BeforeTransfer = await this.HoldToken.getTierAddresses(3);

    await this.HoldToken.transfer(recipients[3], amount);

    const tier3_AfterTransfer = await this.HoldToken.getTierAddresses(1);
    
    expect(tier3_BeforeTransfer.includes(this.creatorAddress)).to.be.true;
    expect(tier3_AfterTransfer.length === 0).to.be.true;
  });

  it("should transfer 88% tokens to recipient", async () => {
    const amount = new BigNumber(5000000e18);

    const balanceBefore = new BigNumber(await this.HoldToken.balanceOf(recipients[1]));
    await this.HoldToken.transfer(recipients[1], amount);
    const balanceNew = new BigNumber(await this.HoldToken.balanceOf(recipients[1]));

    const newExpectedBalance = balanceBefore.plus(amount.multipliedBy(0.88));

    expect(balanceNew).to.be.eql(newExpectedBalance);
  });

  // it("should transfer 88% tokens to recipient", async () => {
  //   const amount = new BigNumber(5000000e18);

  //   const balanceBefore = new BigNumber(await this.HoldToken.balanceOf(recipients[1]));
  //   await this.HoldToken.transfer(recipients[1], amount);
  //   const balanceNew = new BigNumber(await this.HoldToken.balanceOf(recipients[1]));

  //   const newExpectedBalance = balanceBefore.plus(amount.multipliedBy(0.88));
    
  //   expect(balanceNew).to.be.eql(newExpectedBalance);
  // });

  // xit("funds received", async () => {
  //   const recipient =
  //     "0x65bf9eeffbe577b789ed6b2e8277d789389dd2d14c5e895fb1196b333644e013";
  //   const amount = 31400001000000000000000000;
  //   await this.HoldToken.transfer(recipient, amount);
  //   const balance = await this.HoldToken.balanceOf(recipient);
  //   // name.should.equal();
  //   // assert.equal(name, "HoldToken");
  //   expect(balance).to.be.equal(440000000000e18);
  // });
});
