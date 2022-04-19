// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-solidity/contracts/utils/Context.sol";

contract HoldToken is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    address private _burnWallet = 0x000000000000000000000000000000000000dEaD;

    uint private _transferCounter = 0;
    address private _owner;

    mapping (uint8 => address[]) private _tiers;
    mapping (address => uint8) private _userTier;
    mapping (uint => uint16) private _tierMultiplier;
    
    constructor() {
        _name = "SuperHoldToken";
        _symbol = "SHT";

        _tierMultiplier[1] = 1;
        _tierMultiplier[2] = 3;
        _tierMultiplier[3] = 10;
        _tierMultiplier[4] = 31;

        _mint(_msgSender(), 1000000000000 * (10 ** uint256(decimals())));
        _owner = _msgSender();
    }


    function name() public view virtual override returns (string memory) {
        return _name;
    }


    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }


    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function getOwner() public view returns (address) {
        return _owner;
    }

    function package() public view returns (uint256) {
        return 100000 * 10 ** uint256(decimals());
    } 

    function transferCounter() public view returns (uint256) {
        return _transferCounter;
    } 


    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }


    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }


    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }


    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }


    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }


    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }


    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }


    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function getTierAddresses(uint8 tier) public view returns (address[] memory) {
        require(tier > 0 && tier < 5, "given tier do not exists");

        return _tiers[tier];
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        
        uint256 fees = 0;

        if(_transferCounter > 0) {
            _tryUpdateTier(sender);
            fees = _feeDistribution(amount);
        }

        uint256 amountAfterFee = amount - fees;

        _balances[recipient] += amountAfterFee;

        if(_transferCounter > 0) {
            _tryUpdateTier(recipient);
        }

        _transferCounter++;

        emit Transfer(sender, recipient, amountAfterFee);
    }

    function _feeDistribution(uint256 amount) private returns (uint) {
        uint burnFee = (amount * 2) / 100; // 2%
        uint liquidityFee = (amount * 2) / 100; // 2%
        uint developmentFee = (amount * 2) / 100; // 2%
        uint holdersRewards = (amount * 6) / 100; // 6%

        _sendFeeToDeadWallet(burnFee); // burn
        _distributeRewards(holdersRewards); // rewarding
        _balances[_owner] += developmentFee; // send to dev wallet
        // todo: send to LP wallet

        return burnFee + liquidityFee + developmentFee + holdersRewards;
    }

    function _distributeRewards(
        uint256 amount
    ) internal {
        uint settlementUnitsSum = 0;
        settlementUnitsSum += _getSettlementUnitSum(1);
        settlementUnitsSum += _getSettlementUnitSum(2);
        settlementUnitsSum += _getSettlementUnitSum(3);
        settlementUnitsSum += _getSettlementUnitSum(4);

        if(settlementUnitsSum == 0) {
            return;
        }   

        _giveRewardToHolders(amount, 4, settlementUnitsSum);
        _giveRewardToHolders(amount, 3, settlementUnitsSum);
        _giveRewardToHolders(amount, 2, settlementUnitsSum);
        _giveRewardToHolders(amount, 1, settlementUnitsSum);
        // always start from top tiers cos address can be promoted when rewarded and could get double reward
    }

    function _getSettlementUnitSum(uint8 tier) public view returns (uint) {
        address[] memory tierHolders = _tiers[tier];

        if(tierHolders.length == 0) {
            return 0;
        }

        uint settlementUnitsSum = 0;

        for (uint256 i = 0; i < tierHolders.length; i++) {
            settlementUnitsSum += _getSingleSettlementUnits(tier, tierHolders[i]); // check how rounding works
        }

        return settlementUnitsSum;
    }

    function _getSingleSettlementUnits(uint8 tier, address holder) private view returns (uint) {
        return _tierMultiplier[tier] * (_balances[holder] / package());
    }

    function _giveRewardToHolders(
        uint fullRewardAmount,
        uint8 tier,
        uint settlementUnitsSum
        ) internal {
            
        if(_tiers[tier].length == 0) {
            return;
        }

        address[] memory addresses_tier = _tiers[tier];

        for (uint256 i = 0; i < addresses_tier.length; i++) {
            address recipient = addresses_tier[i];

            uint userSettlementUnits = _getSingleSettlementUnits(tier, recipient);
            uint share = (userSettlementUnits * 100000) / settlementUnitsSum;
            uint reward = fullRewardAmount * (share / 100000);

            _balances[recipient] += reward;
            _tryUpdateTier(recipient);
        }
    }
    function terieter(address recipient) public view returns (uint8) {
        return _getValidTier(_balances[recipient]);
    }

    function _tryUpdateTier(
        address recipient
    ) internal {
        uint userCurrentTier = _getCurrentHolderTier(recipient);
        uint8 userNewTier = _getValidTier(_balances[recipient]);
        
        if(userCurrentTier == userNewTier) return;

        if(userCurrentTier != 0) 
            _removeUserFromCurrentTier(recipient);

        if(userNewTier != 0)
            _addUserToTier(recipient, userNewTier);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;

        _balances[account] += (amount * 51) / 100;
        _sendFeeToDeadWallet((amount * 49) / 100);

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _sendFeeToDeadWallet(uint256 amount) private {
        _balances[_burnWallet] += amount;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _removeUserFromCurrentTier(address addressToRemove) private {
        uint8 currentUserTier = _userTier[addressToRemove];
        address[] storage collectionWhereUserIs = _tiers[currentUserTier];
        uint userIndexInCollection = _getElementIndex(collectionWhereUserIs, addressToRemove);
        _removeElementIndex(collectionWhereUserIs, userIndexInCollection);
        delete _userTier[addressToRemove];
    }

    function _addUserToTier(address addressToAdd, uint8 tier) private {
        address[] storage tierColl = _tiers[tier];

        tierColl.push(addressToAdd);
        _userTier[addressToAdd] = tier;
    }

    function _getValidTier(uint userFunds) private pure returns (uint8) {
        if(userFunds < 31400001 * 10 ** 18) return 0;
        if(userFunds >= 31400001 * 10 ** 18 && userFunds < 314000001 * 10 ** 18) return 1;
        if(userFunds >= 314000001 * 10 ** 18 && userFunds < 3140000001 * 10 ** 18) return 2;
        if(userFunds >= 3140000001 * 10 ** 18 && userFunds < 31400000001 * 10 ** 18) return 3;
        return 4; // >= 31400000001
    }

    function _getCurrentHolderTier(address user) private view returns (uint) {
        return _userTier[user];
    }

    function _getElementIndex(address[] storage collection, address addressToFind) private view returns (uint) {
        for (uint i = 0; i < collection.length; i++) {
            if(collection[i] == addressToFind) return i;
        }

        revert();
    }

    function _removeElementIndex(address[] storage collection, uint index) private {
        require(collection.length > 0, "Can't remove from empty array");
        collection[index] = collection[collection.length - 1];
        collection.pop();
    }
}
