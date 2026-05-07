// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A minimal ERC-20 implementation for tests.  Supports
///         `transfer`, `transferFrom`, `approve`, `mint` (test-only),
///         and the standard balance / allowance views.  No events
///         beyond what tests need.
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address a) external view returns (uint256) {
        return _balances[a];
    }

    function allowance(address o, address s) external view returns (uint256) {
        return _allowances[o][s];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _move(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 a = _allowances[from][msg.sender];
        require(a >= value, "ERC20: insufficient allowance");
        unchecked {
            _allowances[from][msg.sender] = a - value;
        }
        _move(from, to, value);
        return true;
    }

    function mint(address to, uint256 value) external {
        _balances[to] += value;
        _totalSupply += value;
        emit Transfer(address(0), to, value);
    }

    function _move(address from, address to, uint256 value) internal {
        require(_balances[from] >= value, "ERC20: balance");
        unchecked {
            _balances[from] -= value;
        }
        _balances[to] += value;
        emit Transfer(from, to, value);
    }
}
