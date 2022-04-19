// const Migrations = artifacts.require("Migrations");
var myContract = artifacts.require("./HoldToken.sol");

module.exports = function (deployer) {
  deployer.deploy(myContract);
};
