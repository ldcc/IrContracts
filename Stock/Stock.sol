pragma solidity ^0.4.24;
pragma experimental "v0.5.0";

import "./StockInterface.sol";

contract Stock is StockInterface {

    string public name;
    string public symbol;
    address public founder;

    constructor(uint256 _initialAmount, string _name, string _symbol) public payable {
        totalSupply = _initialAmount;
        name = _name;
        symbol = _symbol;
        founder = msg.sender;
        holderList.push(this);
        holderList.push(msg.sender);
        holderMap[msg.sender].active = true;
        holderMap[msg.sender].amount = _initialAmount;
        holderMap[msg.sender].frees = _initialAmount;
        licensees[msg.sender][0] = true;
        licensees[msg.sender][1] = true;
    }

    function shareOf(address _owner, uint8 _type) external view returns (uint256 share) {
        Holder memory h = holderMap[_owner];
        if (_type == 1) {
            return h.amount;
        } else if (_type == 2) {
            return h.frees;
        } else {
            return h.amount - h.frees;
        }
    }

    function allowanceOf(address _owner, address _spender) external view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function licenseOf(address _licensee, address _currency) external view returns (bool licensed) {
        return licensees[_licensee][_currency];
    }

    function approve(address _spender, uint256 _value) public {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
    }

    function licensing(address _licensee, address _currency, bool _value) public {
        if (_value) {
            require(msg.sender == founder);
        } else {
            require(msg.sender == _licensee);
            require(licensees[_licensee][_currency]);
        }
        licensees[_licensee][_currency] = _value;
        emit Licensing(msg.sender, _licensee, _currency, _value);
    }

    function transfer(address _to, uint256 _value, uint256 _lockPeriod) public {
        _transfer(msg.sender, _to, _value, _lockPeriod);
        emit Transfer(msg.sender, _to, _value, _lockPeriod);
    }

    function transferFrom(address _from, address _to, uint256 _value, uint256 _lockPeriod) public {
        require(allowed[_from][msg.sender] > 0);
        require(allowed[_from][msg.sender] >= _value);
        _transfer(_from, _to, _value, _lockPeriod);
        emit Transfer(_from, _to, _value, _lockPeriod);
        allowed[_from][msg.sender] -= _value;
    }

    function mulTransfer(address[] _tos, uint256[] _values, uint256[] _lockPeriods) public {
        require(_tos.length == _values.length && _tos.length == _lockPeriods.length);
        for (uint256 i = 0; i < _tos.length; i++) {
            transfer(_tos[i], _values[i], _lockPeriods[i]);
        }
    }

    function withdraw(address _to, address _currency, uint256 _value) public payable {
        require(licensees[msg.sender][_currency]);
        _withdraw(_to, _currency, _value);
        emit Withdraw(msg.sender, _to, _currency, _value);
    }

    function payDividend(address _currency) public payable {
        require(msg.sender == founder);
        uint256 thisBalance = address(this).balance;
        for (uint256 i = 0; i < holderList.length; i++) {
            address addr = holderList[i];
            if (holderMap[addr].amount > 0) {
                uint8 percent = uint8(holderMap[addr].amount * 100 / totalSupply);
                _withdraw(addr, _currency, percent * thisBalance);
            }

        }
        emit PayDividend(msg.sender, _currency);
    }

    function _withdraw(address _to, address _currency, uint256 _value) internal {
        if (_currency == address(0)) {
            require(_value > 0);
            assert(address(this).balance >= _value);
            _to.transfer(_value);
        } else if (_currency == address(this)) {
            _transfer(_currency, _to, _value, 0);
        } else {
            assembly {}
            assert(_currency.call(bytes4(keccak256("transfer")), this, _to, _value));
        }
    }

    function _transfer(address _from, address _to, uint256 _value, uint256 _lockPeriod) private {
        require(_value > 0);
        Holder storage hf = holderMap[_from];
        require(hf.active);
        require(hf.amount >= _value);
        if (hf.frees < _value) {
            _upgradeHolder(hf);
        }
        require(hf.frees >= _value);
        Holder storage ht = holderMap[_to];
        uint256 oldHtAmount = ht.amount;
        if (!ht.active) {
            holderList.push(_to);
            ht.active = true;
        }

        // transfer
        hf.amount -= _value;
        hf.frees -= _value;
        ht.amount += _value;
        if (_lockPeriod > 0) {
            uint256 liftedPeriod = _lockPeriod + block.timestamp;
            Share memory share = Share({
                locks : _value,
                liftedPeriod : liftedPeriod});
            ht.shares.push(share);
        } else {
            ht.frees += _value;
        }
        assert(oldHtAmount < ht.amount);
    }

    function _upgradeHolder(Holder storage _h) private {
        uint256 unlocks = 0;
        uint256 present = block.timestamp;
        for (uint8 i = 0; i < _h.shares.length; i++) {
            if (_h.shares[i].locks == 0) {
                continue;
            }
            if (present >= _h.shares[i].liftedPeriod) {
                unlocks += _h.shares[i].locks;
                delete _h.shares[i];
            }
        }
        if (unlocks > 0) {
            _h.frees += unlocks;
        }
    }

}
