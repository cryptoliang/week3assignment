// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

error ZeroAmount();
error TransferFailed();
error NotEnoughBalance(uint balance, uint need);

contract ChequeBank {

    mapping(address => uint) public addressToBalance;

    struct ChequeInfo {
        uint amount;
        bytes32 chequeId;
        uint32 validFrom;
        uint32 validThru;
        address payee;
        address payer;
    }

    struct SignOverInfo {
        uint8 counter;
        bytes32 chequeId;
        address oldPayee;
        address newPayee;
    }

    struct Cheque {
        ChequeInfo chequeInfo;
        bytes sig;
    }

    struct SignOver {
        SignOverInfo signOverInfo;
        bytes sig;
    }

    function deposit() payable external {
        if (msg.value == 0) revert ZeroAmount();
        addressToBalance[msg.sender] += msg.value;
    }

    function withdraw(uint amount) external {
        withdrawTo(amount, payable(msg.sender));
    }

    function withdrawTo(uint amount, address payable recipient) public {
        if (amount == 0) revert ZeroAmount();
        uint balance = addressToBalance[msg.sender];
        if (amount > balance) revert NotEnoughBalance(balance, amount);

        addressToBalance[msg.sender] = balance - amount;
        (bool ok,) = recipient.call{value : amount}("");
        if (!ok) revert TransferFailed();
    }

    function redeem(Cheque memory chequeData) external {}

    function revoke(bytes32 chequeId) external {}

    function notifySignOver(
        SignOver memory signOverData
    ) external {}

    function redeemSignOver(
        Cheque memory chequeData,
        SignOver[] memory signOverData
    ) external {}

    function isChequeValid(
        address payee,
        Cheque memory chequeData,
        SignOver[] memory signOverData
    ) view public returns (bool) {}
}