// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

error ZeroAmount();
error TransferFailed();
error NotEnoughBalance(uint balance, uint need);
error InvalidSignature();
error InvalidRedeemTiming(uint currentBlockNumber);
error RevokedCheque();
error AlreadyRedeemed();
error AlreadySignedOver();
error InvalidSignOverChain();
error MaxSignOverReached();

contract ChequeBank {

    mapping(address => uint) public addressToBalance;
    mapping(bytes32 => mapping(address => bool)) public revocations;
    mapping(bytes32 => bool) public redemptions;
    mapping(bytes32 => mapping(uint8 => mapping(address => bool))) public reportedSignOvers;
    uint constant MAX_SIGN_OVER_COUNT = 6;

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
        if (!isValidRedeemTiming(chequeInfo)) revert InvalidRedeemTiming(block.number);
        if (!isValidChequeSig(chequeData)) revert InvalidSignature();
        if (revocations[chequeInfo.chequeId][chequeInfo.payer]) revert RevokedCheque();
        if (redemptions[chequeInfo.chequeId]) revert AlreadyRedeemed();
        if (reportedSignOvers[chequeInfo.chequeId][1][chequeInfo.payee]) revert AlreadySignedOver();

        redemptions[chequeInfo.chequeId] = true;

        _withdraw(chequeInfo.amount, chequeInfo.payer, payable(chequeInfo.payee));
    }

    function revoke(bytes32 chequeId) external {
        if (redemptions[chequeId]) revert AlreadyRedeemed();
        revocations[chequeId][msg.sender] = true;
    }

    function notifySignOver(SignOver memory signOverData) external {
        SignOverInfo memory info = signOverData.signOverInfo;
        if (info.counter > MAX_SIGN_OVER_COUNT) revert MaxSignOverReached();
        if (revocations[info.chequeId][info.oldPayee]) revert RevokedCheque();
        if (redemptions[info.chequeId]) revert AlreadyRedeemed();
        if (!isValidSignOverSig(signOverData)) revert InvalidSignature();
        if (reportedSignOvers[info.chequeId][info.counter][info.oldPayee]) revert AlreadySignedOver();

        reportedSignOvers[info.chequeId][info.counter][info.oldPayee] = true;
    }

    function redeemSignOver(Cheque memory chequeData, SignOver[] memory signOvers) external {
        ChequeInfo memory chequeInfo = chequeData.chequeInfo;
        if (!isValidRedeemTiming(chequeInfo)) revert InvalidRedeemTiming(block.number);
        if (!isValidChequeSig(chequeData)) revert InvalidSignature();
        if (redemptions[chequeInfo.chequeId]) revert AlreadyRedeemed();

        (bool ok, address lastPayer, address lastPayee) = verifySignOverChain(chequeInfo, signOvers);
        if (!ok) revert InvalidSignOverChain();

        if (revocations[chequeInfo.chequeId][lastPayer]) revert RevokedCheque();
        if (reportedSignOvers[chequeInfo.chequeId][uint8(signOvers.length + 1)][lastPayee]) revert AlreadySignedOver();

        redemptions[chequeInfo.chequeId] = true;
        _withdraw(chequeInfo.amount, chequeInfo.payer, payable(lastPayee));
    }

    function isChequeValid(address payee, Cheque memory chequeData, SignOver[] memory signOvers) view public returns (bool) {
        ChequeInfo memory chequeInfo = chequeData.chequeInfo;
        if (!isValidRedeemTiming(chequeInfo)) return false;
        if (!isValidChequeSig(chequeData)) return false;
        if (redemptions[chequeInfo.chequeId]) return false;

        (bool ok, address lastPayer, address lastPayee) = verifySignOverChain(chequeInfo, signOvers);
        if (!ok) return false;

        if (lastPayee != payee) return false;
        if (revocations[chequeInfo.chequeId][lastPayer]) return false;
        if (reportedSignOvers[chequeInfo.chequeId][uint8(signOvers.length + 1)][lastPayee]) return false;
        if (chequeInfo.amount > addressToBalance[chequeInfo.payer]) return false;

        return true;
    }

    function verifySignOverChain(ChequeInfo memory chequeInfo, SignOver[] memory signOvers)
        private pure returns (bool _ok, address _lastPayer, address _lastPayee) {

        uint len = signOvers.length;
        if (len > MAX_SIGN_OVER_COUNT) return (false, address(0), address(0));

        SignOver[] memory orderedSignOvers = new SignOver[](len);

        for (uint i = 0; i < len; i++) {
            uint8 counter = signOvers[i].signOverInfo.counter;
            if (counter > len) return (false, address(0), address(0));
            if (signOvers[i].signOverInfo.chequeId != chequeInfo.chequeId) return (false, address(0), address(0));
            if (!isValidSignOverSig(signOvers[i])) return (false, address(0), address(0));
            orderedSignOvers[counter - 1] = signOvers[i];
        }

        address prevPayee = chequeInfo.payee;

        for (uint i = 0; i < len; i++) {
            if (orderedSignOvers[i].signOverInfo.counter != i + 1) return (false, address(0), address(0));
            if (orderedSignOvers[i].signOverInfo.oldPayee != prevPayee) return (false, address(0), address(0));
            prevPayee = orderedSignOvers[i].signOverInfo.newPayee;
        }

        address lastPayer = len > 0 ? orderedSignOvers[len - 1].signOverInfo.oldPayee : chequeInfo.payer;
        address lastPayee = len > 0 ? orderedSignOvers[len - 1].signOverInfo.newPayee : chequeInfo.payee;
        return (true, lastPayer, lastPayee);
    }

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

    function isValidChequeSig(Cheque memory cheque) private view returns (bool) {
        ChequeInfo memory chequeInfo = cheque.chequeInfo;
        bytes memory encodedData = abi.encodePacked(chequeInfo.chequeId, chequeInfo.payer, chequeInfo.payee,
            chequeInfo.amount, address(this), chequeInfo.validFrom, chequeInfo.validThru);
        bytes32 hash = prefixed(keccak256(encodedData));
        return recoverSigner(hash, cheque.sig) == chequeInfo.payer;
    }

    function isValidSignOverSig(SignOver memory signOver) private pure returns (bool) {
        SignOverInfo memory info = signOver.signOverInfo;
        bytes4 MAGIC_NUMBER = 0xFFFFDEAD;
        bytes memory encodedData = abi.encodePacked(MAGIC_NUMBER, info.counter, info.chequeId, info.oldPayee, info.newPayee);
        bytes32 hash = prefixed(keccak256(encodedData));
        return recoverSigner(hash, signOver.sig) == info.oldPayee;
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