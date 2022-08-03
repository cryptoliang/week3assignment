// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

error ZeroAmount();
error TransferFailed();
error NotEnoughBalance(uint balance, uint need);
error InvalidSignature();
error InvalidRedeemTiming(uint currentBlockNumber);
error Unauthorized();

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
        _withdraw(amount, msg.sender, recipient);
    }

    function redeem(Cheque memory chequeData) external {
        ChequeInfo memory chequeInfo = chequeData.chequeInfo;
        if (msg.sender != chequeInfo.payee) revert Unauthorized();
        if (!isValidRedeemTiming(chequeInfo)) revert InvalidRedeemTiming(block.number);
        if (!isValidSig(chequeData)) revert InvalidSignature();

        _withdraw(chequeInfo.amount, chequeInfo.payer, payable(chequeInfo.payee));
    }

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

    function _withdraw(uint amount, address from, address payable to) private {
        if (amount == 0) revert ZeroAmount();
        uint balance = addressToBalance[from];
        if (amount > balance) revert NotEnoughBalance(balance, amount);

        addressToBalance[from] = balance - amount;
        (bool ok,) = to.call{value : amount}("");
        if (!ok) revert TransferFailed();
    }

    function isValidRedeemTiming(ChequeInfo memory chequeInfo) private view returns (bool) {
        if (chequeInfo.validThru != 0 && chequeInfo.validFrom > chequeInfo.validThru) return false;
        if (chequeInfo.validThru != 0 && block.number > chequeInfo.validThru) return false;
        if (block.number < chequeInfo.validFrom) return false;
        return true;
    }

    function isValidSig(Cheque memory cheque) private view returns (bool) {
        ChequeInfo memory chequeInfo = cheque.chequeInfo;
        bytes memory encodedData = abi.encodePacked(chequeInfo.chequeId, chequeInfo.payer, chequeInfo.payee,
            chequeInfo.amount, address(this), chequeInfo.validFrom, chequeInfo.validThru);
        bytes32 hash = prefixed(keccak256(encodedData));
        return recoverSigner(hash, cheque.sig) == chequeInfo.payer;
    }

    function splitSignature(bytes memory sig) private pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65);

        assembly {
        // first 32 bytes, after the length prefix.
            r := mload(add(sig, 32))
        // second 32 bytes.
            s := mload(add(sig, 64))
        // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function recoverSigner(bytes32 message, bytes memory sig) private pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(sig);

        return ecrecover(message, v, r, s);
    }

    /// builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}