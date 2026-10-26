// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

contract TokenContract {
    address public owner;

    struct Receivers {
        string name;
        uint256 tokens;
    }

    mapping (address => Receivers) public users;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor() {
        owner = msg.sender;
        users[owner].tokens = 100;
    }

    function double(uint value) public pure returns (uint) {
        return value * 2;
    }

    function register(string memory name) public {
        users[msg.sender].name = name;
    }

    function giveToken(address _receiver, uint256 amount) onlyOwner public {
        require(users[owner].tokens >= amount);
        users[owner].tokens -= amount;
        users[_receiver].tokens += amount;
    }

    function buyToken(uint256 amount) public payable {
        uint256 cost = amount * 5 ether;
        // comprobar que se envía suficiente Ether
        require(msg.value >= cost, "Error: Ether insuficiente.");
        // comprobar que el propietario tiene suficientes tokens
        require(users[owner].tokens >= amount, "Error: El propietario no tiene tokens suficientes.");
        
        // actualizar saldos
        users[owner].tokens -= amount;
        users[msg.sender].tokens += amount;
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}